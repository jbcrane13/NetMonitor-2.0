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
    /// The last scan that ran to the end, as published with `lastScanDate` (#589).
    public private(set) var completedScanDevices: [DiscoveredDevice] = []

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
            identity: device.identity,
            bonjourClaims: device.bonjourClaims
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
        await mergeCompanionDevices(filter: scanTarget.filter, profileID: profileID, macConnected: macStillConnected)
        await identifyDevices(context: context, nameResolver: nameResolver)
        await flushToMainActor(progress: 0.95, profileID: profileID)

        // Final sort and flush
        let sorted = await engine.accumulator.sortedSnapshot().map { Self.withProfile($0, profileID: profileID) }
        // Stopped during the companion merge or identity steps: not a finished scan, and its
        // engine may already hold a newer scan's devices (#582).
        guard !Task.isCancelled else { return }
        publishCompletedScan(Self.finalDevices(scanned: sorted, previous: staleDevices), cacheKey: cacheKey)
    }

    /// Publishes a scan that ran to the end. Only such a scan moves `lastScanDate` and
    /// `completedScanDevices`: a stopped one leaves a partial list (#582, #589).
    private func publishCompletedScan(_ result: [DiscoveredDevice], cacheKey: String) {
        discoveredDevices = result
        cachedDevicesByProfileID[cacheKey] = result
        persistCachedDevices()
        scanProgress = 1.0
        scanPhase = .done
        completedScanDevices = result
        lastScanDate = Date()
    }

    /// Identity after the Mac companion's devices are merged: the enrolled UniFi controller's
    /// list, then guesses from names, asking DNS for devices whose names don't identify them.
    /// iOS runs the hostname step here instead of in the pipeline, so a guess sees the
    /// companion's makers and names, and companion-only devices get a lookup (ADR-022).
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
            nameResolver: { await nameResolver.resolve(ipAddress: $0) },
            // Run after the companion merge instead (identifyDevices).
            includeHostnameIdentity: false
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

    /// The oldest a Mac's device list may be and still count as the devices answering now (#598).
    nonisolated public static let companionListFreshness: TimeInterval = 120

    /// The paired Mac's devices as this scan's sightings, and whether they are fresh: only while the
    /// Mac is connected and its list arrived within `companionListFreshness`. A stale list (the Mac
    /// disconnected, or its list is old) is left out of the scan (`mergeCompanion`) (#598).
    nonisolated public static func companionSightings(
        list: DeviceListPayload?,
        receivedAt: Date?,
        macConnected: Bool,
        now: Date,
        includes: (String) -> Bool,
        profileID: UUID?
    ) -> (devices: [DiscoveredDevice], fresh: Bool) {
        guard let list else { return ([], false) }
        let fresh = macConnected && receivedAt.map { now.timeIntervalSince($0) < companionListFreshness } == true
        let devices = list.devices.filter { $0.isOnline && includes($0.ipAddress) }.map { macDevice in
            DiscoveredDevice(
                ipAddress: macDevice.ipAddress,
                hostname: macDevice.hostname,
                vendor: macDevice.vendor,
                macAddress: macDevice.macAddress.isEmpty ? nil : macDevice.macAddress,
                latency: nil,
                discoveredAt: receivedAt ?? now,
                source: .macCompanion,
                networkProfileID: profileID
            )
        }
        return (devices, fresh)
    }

    /// Merge devices discovered by the paired Mac into accumulated results, only when its list is
    /// fresh (`companionSightings`).
    private func mergeCompanionDevices(filter: ScanFilter, profileID: UUID?, macConnected: Bool) async {
        await Self.mergeCompanion(
            Self.companionSightings(
                list: macConnectionService?.lastDeviceList, receivedAt: macConnectionService?.lastDeviceListReceivedAt,
                macConnected: macConnected, now: Date(), includes: { filter.contains(ipAddress: $0) }, profileID: profileID
            ),
            into: engine.accumulator
        )
    }

    /// Adds the Mac's devices to a scan as answers when its list is fresh. A stale list adds nothing:
    /// merging it, even unconfirmed, would lend a device the Mac saw before (its MAC, name, maker) to
    /// whatever the phone finds at that address now, such as another device DHCP gave it to (#598).
    /// A device only the stale list has is simply absent, which saved presence counts as a miss.
    nonisolated public static func mergeCompanion(
        _ sightings: (devices: [DiscoveredDevice], fresh: Bool),
        into accumulator: ScanAccumulator
    ) async {
        guard sightings.fresh else { return }
        for device in sightings.devices {
            await accumulator.upsert(device)
        }
    }
}
