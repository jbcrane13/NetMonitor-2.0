import Foundation
import Network
import NetworkScanKit

@MainActor
@Observable
public final class DeviceDiscoveryService: DeviceDiscoveryServiceProtocol {
    /// Shared instance for app-wide use. Prefer injecting via init for testability.
    public static let shared = DeviceDiscoveryService()

    // MARK: - Observable properties (read by SwiftUI on MainActor)

    public private(set) var discoveredDevices: [DiscoveredDevice] = []
    public private(set) var isScanning: Bool = false
    public private(set) var scanProgress: Double = 0
    public private(set) var scanPhase: ScanDisplayPhase = .idle
    public private(set) var lastScanDate: Date?

    // MARK: - Private scan filter / target types

    private enum ScanFilter {
        case prefix(String)
        case network(NetworkUtilities.IPv4Network)

        func contains(ipAddress: String) -> Bool {
            switch self {
            case .prefix(let prefix):
                return ipAddress.hasPrefix(prefix + ".")
            case .network(let network):
                return network.contains(ipAddress: ipAddress)
            }
        }
    }

    private struct ScanTarget {
        let hosts: [String]
        let filter: ScanFilter
    }

    // MARK: - Private state

    private let engine = ScanEngine()
    private let macConnectionService: (any MacConnectionServiceProtocol)?
    private let userDefaults: UserDefaults

    private var scanTask: Task<Void, Never>?
    private var cachedDevicesByProfileID: [String: [DiscoveredDevice]] = [:]
    private var progressCoalescer = ScanProgressCoalescer()

    private static let deviceCacheStorageKey = "netmonitor.deviceCacheByProfileID"

    public init(
        macConnectionService: (any MacConnectionServiceProtocol)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.macConnectionService = macConnectionService
        self.userDefaults = userDefaults
        loadCachedDevices()
    }

    private let maxHostsPerScan = 1024

    /// Devices are cached per network. A profile's id is per network (see
    /// `NetworkProfileManager.resolveLocalNetworkID`); a scan without a profile is keyed by
    /// the network it covers, so it never hands one network's devices to another.
    nonisolated private func cacheKey(for profile: NetworkProfile?, target: ScanTarget) -> String {
        profile?.id.uuidString ?? Self.autoCacheKey(for: target.filter)
    }

    nonisolated private static func autoCacheKey(for filter: ScanFilter) -> String {
        switch filter {
        case .prefix(let prefix):
            return "auto|\(prefix)"
        case .network(let network):
            return "auto|\(NetworkUtilities.uint32ToIPv4(network.networkAddress))/\(network.prefixLength)"
        }
    }

    /// Copies `device` with `profileID`. Mid-scan snapshots pass `keepCached: false` so rows
    /// don't show "Cached" before ICMP has had a chance to answer (#378).
    nonisolated static func withProfile(_ device: DiscoveredDevice, profileID: UUID?, keepCached: Bool = true) -> DiscoveredDevice {
        DiscoveredDevice(
            id: device.id,
            ipAddress: device.ipAddress,
            hostname: device.hostname,
            vendor: device.vendor,
            macAddress: device.macAddress,
            latency: device.latency,
            discoveredAt: device.discoveredAt,
            source: device.source,
            networkProfileID: profileID,
            isCached: keepCached && device.isCached,
            friendlyName: device.friendlyName,
            manufacturer: device.manufacturer,
            modelName: device.modelName
        )
    }

    /// The devices a completed scan publishes and persists. An empty scan keeps the previous
    /// list, marked cached: nothing answered, so those devices may have left (#378).
    nonisolated static func finalDevices(scanned: [DiscoveredDevice], previous: [DiscoveredDevice]) -> [DiscoveredDevice] {
        guard scanned.isEmpty else { return scanned }
        return previous.map { $0.withCached(true) }
    }

    private func loadCachedDevices() {
        guard let data = userDefaults.data(forKey: Self.deviceCacheStorageKey),
              let decoded = try? JSONDecoder().decode([String: [DiscoveredDevice]].self, from: data) else {
            return
        }
        cachedDevicesByProfileID = decoded
    }

    private func persistCachedDevices() {
        guard let data = try? JSONEncoder().encode(cachedDevicesByProfileID) else { return }
        userDefaults.set(data, forKey: Self.deviceCacheStorageKey)
    }

    // MARK: - Batched UI update helpers

    /// Flush accumulated devices and progress to UI.
    private func flushToMainActor(
        progress: Double? = nil,
        phase: ScanDisplayPhase? = nil,
        profileID: UUID? = nil
    ) async {
        let devices = await engine.accumulator.snapshot().map { Self.withProfile($0, profileID: profileID) }
        self.discoveredDevices = devices
        if let progress {
            self.scanProgress = progress
        }
        if let phase {
            self.scanPhase = phase
        }
    }

    // MARK: - Public API

    public func scanNetwork(subnet: String? = nil) async {
        guard !isScanning else { return }
        let task = Task {
            await self.performScan(subnet: subnet, profile: nil)
        }
        scanTask = task
        await task.value
    }

    public func scanNetwork(profile: NetworkProfile?) async {
        guard !isScanning else { return }
        let task = Task {
            await self.performScan(subnet: nil, profile: profile)
        }
        scanTask = task
        await task.value
    }

    private func performScan(subnet: String? = nil, profile: NetworkProfile? = nil) async {
        let scanTarget: ScanTarget
        if let profile {
            scanTarget = makeScanTarget(profile: profile)
        } else {
            scanTarget = makeScanTarget(subnet: subnet)
        }
        let cacheKey = cacheKey(for: profile, target: scanTarget)
        // Only cached devices inside the network being scanned. A cache saved by an older
        // build, when every Wi-Fi network shared one id, can hold another network's devices.
        let staleDevices = (cachedDevicesByProfileID[cacheKey] ?? []).filter {
            scanTarget.filter.contains(ipAddress: $0.ipAddress)
        }
        let profileID = profile?.id

        await engine.reset()
        isScanning = true
        scanProgress = 0
        scanPhase = .arpScan
        discoveredDevices = staleDevices
        progressCoalescer = ScanProgressCoalescer()

        defer {
            isScanning = false
            scanPhase = .idle
            lastScanDate = Date()
        }

        // If paired with Mac, kick off its scan early (it runs in parallel)
        let macConnected = macConnectionService?.connectionState.isConnected ?? false
        if macConnected {
            await macConnectionService?.send(command: CommandPayload(action: .scanDevices))
        }

        // Start Bonjour discovery early — runs during ARP + TCP phases
        let bonjourService = BonjourDiscoveryService()
        bonjourService.startDiscovery()
        defer { bonjourService.stopDiscovery() }

        // Build ScanContext — use the profile's interface for local IP detection
        let filter = scanTarget.filter
        let interfaceName = (profile?.interfaceName.isEmpty == false) ? (profile?.interfaceName ?? "en0") : "en0"
        let context = ScanContext(
            hosts: scanTarget.hosts,
            subnetFilter: { filter.contains(ipAddress: $0) },
            localIP: NetworkUtilities.detectLocalIPAddress(interface: interfaceName),
            requiredInterfaceType: .wifi
        )

        // Names through the gateway's DNS too: a VPN's DNS (Tailscale) knows no LAN names.
        let nameResolver = GatewayNameResolver(interface: interfaceName)

        let pipeline = Self.makePipeline(bonjourService: bonjourService, nameResolver: nameResolver)

        // Run the scan engine
        let engineRef = engine
        _ = await engineRef.scan(pipeline: pipeline, context: context) { [weak self] progress, phaseID in
            let shouldPublish = await MainActor.run {
                guard let self else { return false }
                return self.progressCoalescer.shouldPublish(
                    progress: progress,
                    phase: phaseID.rawValue,
                    timestamp: ProcessInfo.processInfo.systemUptime
                )
            }
            guard shouldPublish else { return }

            let snapshot = await engineRef.accumulator.snapshot()
            await MainActor.run {
                guard let self else { return }
                self.scanProgress = progress
                self.discoveredDevices = snapshot.map { Self.withProfile($0, profileID: profileID, keepCached: false) }
                if let phase = ScanDisplayPhase(phaseID: phaseID) {
                    self.scanPhase = phase
                }
            }
        }

        guard !Task.isCancelled else { return }

        // Phase: Mac companion merge
        scanPhase = .companion
        scanProgress = 0.90

        let macStillConnected = macConnectionService?.connectionState.isConnected ?? false
        if macStillConnected {
            await macConnectionService?.send(command: CommandPayload(action: .refreshDevices))
            try? await Task.sleep(for: .seconds(1))
        }
        guard !Task.isCancelled else { return }
        await mergeCompanionDevices(filter: scanTarget.filter, profileID: profileID)
        await identifyDevices(context: context, nameResolver: nameResolver)
        await flushToMainActor(progress: 0.95, profileID: profileID)

        // Final sort and flush
        let sorted = await engine.accumulator.sortedSnapshot().map { Self.withProfile($0, profileID: profileID) }
        let result = Self.finalDevices(scanned: sorted, previous: staleDevices)
        discoveredDevices = result
        cachedDevicesByProfileID[cacheKey] = result
        persistCachedDevices()
        scanProgress = 1.0
        scanPhase = .done
    }

    /// Fills makers and models after every scan and companion source: the enrolled UniFi
    /// controller's list, then guesses from names, last so better makers win over them (#439).
    private func identifyDevices(context: ScanContext, nameResolver: GatewayNameResolver) async {
        await UniFiInventoryPhase().execute(context: context, accumulator: engine.accumulator) { _ in }
        await HostnameIdentityPhase(lookUpName: { await nameResolver.resolve(ipAddress: $0) })
            .execute(context: context, accumulator: engine.accumulator) { _ in }
    }

    /// The standard pipeline, fed by this scan's Bonjour browser.
    private static func makePipeline(bonjourService: BonjourDiscoveryService, nameResolver: GatewayNameResolver) -> ScanPipeline {
        ScanPipeline.standard(
            bonjourServiceProvider: {
                await MainActor.run {
                    bonjourService.discoveredServices.map {
                        BonjourServiceInfo(name: $0.name, type: $0.type, domain: $0.domain, txtRecord: $0.txtRecords)
                    }
                }
            },
            bonjourStopProvider: {
                await MainActor.run { bonjourService.stopDiscovery() }
            },
            nameResolver: { await nameResolver.resolve(ipAddress: $0) }
        )
    }

    public func stopScan() {
        isScanning = false
        scanTask?.cancel()
    }

    /// Called when the device has joined a different network: drops the old network's
    /// devices from the list, lets a scan of the old network wind down (it shares `engine`),
    /// then scans the new one. The old network's devices stay in its cache for next time.
    public func rescanAfterNetworkChange(profile: NetworkProfile?) async {
        let running = scanTask
        running?.cancel()
        await running?.value
        isScanning = false
        discoveredDevices = []
        scanProgress = 0
        scanPhase = .idle
        await scanNetwork(profile: profile)
    }

    public func cachedDevices(for profile: NetworkProfile?) -> [DiscoveredDevice] {
        // Views read this often, so build only the filter, not the host list.
        let filter: ScanFilter = profile.map { .network($0.network) } ?? makeScanTarget(subnet: nil).filter
        let key = profile?.id.uuidString ?? Self.autoCacheKey(for: filter)
        return (cachedDevicesByProfileID[key] ?? []).filter { filter.contains(ipAddress: $0.ipAddress) }
    }

    // MARK: - Scan Target Planning

    nonisolated private func makeScanTarget(profile: NetworkProfile) -> ScanTarget {
        let hosts = profile.network.hostAddresses(limit: maxHostsPerScan)
        return ScanTarget(hosts: hosts, filter: .network(profile.network))
    }

    nonisolated private func makeScanTarget(subnet: String?) -> ScanTarget {
        let localIP = NetworkUtilities.detectLocalIPAddress()

        if let subnet, !subnet.isEmpty {
            return ScanTarget(
                hosts: hostsForSubnetPrefix(subnet, excluding: localIP),
                filter: .prefix(subnet)
            )
        }

        if let network = NetworkUtilities.detectLocalIPv4Network() {
            let hosts = network.hostAddresses(limit: maxHostsPerScan)
            if !hosts.isEmpty {
                return ScanTarget(hosts: hosts, filter: .network(network))
            }
        }

        let fallbackSubnet = NetworkUtilities.detectSubnet() ?? "192.168.1"
        return ScanTarget(
            hosts: hostsForSubnetPrefix(fallbackSubnet, excluding: localIP),
            filter: .prefix(fallbackSubnet)
        )
    }

    nonisolated private func hostsForSubnetPrefix(_ subnet: String, excluding ipToSkip: String?) -> [String] {
        var hosts: [String] = []
        hosts.reserveCapacity(254)

        for host in 1...254 {
            let ip = "\(subnet).\(host)"
            if ip != ipToSkip {
                hosts.append(ip)
            }
        }

        return hosts
    }

    // MARK: - Mac Companion Merge

    /// Merge devices discovered by the paired Mac into accumulated results.
    private func mergeCompanionDevices(filter: ScanFilter, profileID: UUID?) async {
        let macDevices = macConnectionService?.lastDeviceList?.devices
        guard let macDevices else { return }

        for macDevice in macDevices where macDevice.isOnline {
            guard filter.contains(ipAddress: macDevice.ipAddress) else { continue }

            await engine.accumulator.upsert(DiscoveredDevice(
                ipAddress: macDevice.ipAddress,
                hostname: macDevice.hostname,
                vendor: macDevice.vendor,
                macAddress: macDevice.macAddress.isEmpty ? nil : macDevice.macAddress,
                latency: nil,
                discoveredAt: Date(),
                source: .macCompanion,
                networkProfileID: profileID
            ))
        }
    }
}
