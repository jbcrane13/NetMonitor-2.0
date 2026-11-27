import Foundation
import Network
import NetworkScanKit
import Synchronization

@MainActor
@Observable
public final class DeviceDiscoveryService: DeviceDiscoveryServiceProtocol {
    /// Shared instance for app-wide use. Prefer injecting via init for testability.
    public static let shared = DeviceDiscoveryService()

    // MARK: - Observable properties (read by SwiftUI on MainActor)

    public private(set) var discoveredDevices: [DiscoveredDevice] = []
    public private(set) var isScanning: Bool = false {
        didSet { Self.scanningNow.withLock { $0 = isScanning } }
    }

    /// Whether the phone's scan runs now, readable from any thread: the identity route checks it at
    /// the send itself (#642). The app runs one discovery service, so this is its `isScanning`.
    private nonisolated static let scanningNow = Mutex(false)
    public nonisolated static var isScanningNow: Bool { scanningNow.withLock { $0 } }
    public private(set) var scanProgress: Double = 0
    public private(set) var scanPhase: ScanDisplayPhase = .idle
    public private(set) var lastScanDate: Date?
    /// The last scan that ran to the end, as published with `lastScanDate` (#589).
    public private(set) var completedScanDevices: [DiscoveredDevice] = []
    /// The Mac's answers for the last completed scan, kept apart from its devices (#585).
    public private(set) var completedScanMacSightings: [DiscoveredDevice] = []
    /// The Mac's answers gathered by the running scan, published with it.
    private var pendingMacSightings: [DiscoveredDevice] = []

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
        // An inventory Mac sends its list after each of its own scans (#585): no request, no wait.
        if macStillConnected, macConnectionService?.macOffersInventory != true {
            await macConnectionService?.send(command: CommandPayload(action: .refreshDevices))
            try? await Task.sleep(for: .seconds(1))
        }
        guard !Task.isCancelled else { return }
        await mergeCompanionDevices(filter: scanTarget.filter, profile: profile, macConnected: macStillConnected)
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
        completedScanMacSightings = pendingMacSightings
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
}

// MARK: - Mac Companion Merge

extension DeviceDiscoveryService {

    /// The oldest a Mac's device list may be and still count as the devices answering now (#598).
    nonisolated public static let companionListFreshness: TimeInterval = 120

    /// The paired Mac's devices as this scan's sightings, and whether they are fresh: only while the
    /// Mac is connected and its list arrived within `companionListFreshness`. A stale list (the Mac
    /// disconnected, or its list is old) is left out of the scan (`mergeCompanion`) (#598). A device
    /// with `members` (a Mac with #594 PR2) gives one sighting per interface that answered the Mac's
    /// latest scan, when that scan is newer than `ownLastScan` (this phone's own last scan of the
    /// network); a newly received list is not proof of a new scan. The Mac's scan is placed on this
    /// phone's clock as `receivedAt - scanAge`, never by comparing the two devices' clocks (#619).
    /// A list that carries `network` is an `inventory.v1` Mac's (#585) and adds nothing to the scan,
    /// whatever its heartbeat said yet: its answers refresh existing rows apart (`inventorySightings`).
    nonisolated public static func companionSightings(
        list: DeviceListPayload?,
        receivedAt: Date?,
        macConnected: Bool,
        now: Date,
        includes: (String) -> Bool,
        profileID: UUID?,
        ownLastScan: Date? = nil
    ) -> (devices: [DiscoveredDevice], fresh: Bool) {
        guard let list, list.network == nil else { return ([], false) }
        let fresh = macConnected && receivedAt.map { now.timeIntervalSince($0) < companionListFreshness } == true
        func sighting(ipAddress: String, macAddress: String?, of device: DeviceInfo, named: Bool = true) -> DiscoveredDevice {
            DiscoveredDevice(
                ipAddress: ipAddress,
                hostname: named ? device.hostname : nil,
                vendor: device.vendor,
                macAddress: (macAddress ?? "").isEmpty ? nil : macAddress,
                latency: nil,
                discoveredAt: receivedAt ?? now,
                source: .macCompanion,
                networkProfileID: profileID
            )
        }
        let devices = list.devices.flatMap { device -> [DiscoveredDevice] in
            // A Mac before #594 PR2: the device's one address, when it answered the Mac's latest scan.
            guard let members = device.members else {
                return device.isOnline && includes(device.ipAddress)
                    ? [sighting(ipAddress: device.ipAddress, macAddress: device.macAddress, of: device)] : []
            }
            // Each interface that answered a Mac scan newer than the phone's own (#594 PR2), with
            // the Mac's scan placed on this phone's clock by its age when sent (#619).
            return members.filter { member in
                // A negative, non-finite or absurd age is rejected, never read as a scan at sending
                // (#585 review): a Mac whose clock went back would renew its old answers.
                if member.scanAge != nil, MacInventory.validAge(member.scanAge) == nil {
                    return false
                }
                let scannedHere = MacInventory.validAge(member.scanAge).map { (receivedAt ?? now).addingTimeInterval(-$0) }
                return member.answeredLatestScan && includes(member.ipAddress)
                    && (ownLastScan.map { own in scannedHere.map { $0 > own } ?? false } ?? true)
            }.map { member in
                // The device's name is its primary's: another interface's sighting carries none, so
                // one without a MAC still matches the phone's own row at its address (#619).
                let isPrimary = member.isPrimary ?? (members.count == 1)
                return sighting(ipAddress: member.ipAddress, macAddress: member.macAddress, of: device, named: isPrimary)
            }
        }
        return (devices, fresh)
    }

    /// The paired Mac's devices for this scan: an older Mac's list merged into the scan when fresh
    /// (`companionSightings`); an inventory Mac's answers kept apart for the reconciler, only while
    /// its inventory is live for the scanned network (#585).
    private func mergeCompanionDevices(filter: ScanFilter, profile: NetworkProfile?, macConnected: Bool) async {
        let list = macConnectionService?.lastDeviceList, receivedAt = macConnectionService?.lastDeviceListReceivedAt
        let ownLastScan = ScanHistory().lastScanTime(for: profile?.id)
        pendingMacSightings = []
        if let list, list.network != nil {
            // The phone's current network, not the scanned or selected profile (#624).
            pendingMacSightings = profile.map { scanned in
                Self.inventoryMacSightings(
                    list: list, receivedAt: receivedAt, link: macConnected ? macConnectionService?.linkPath : nil,
                    current: NetworkProfileManager.currentProfile(), scanned: scanned, gateway: NetworkUtilities.detectRoutedGateway(),
                    ownLastScan: ownLastScan, now: Date()
                )
            } ?? []
            return
        }
        await Self.mergeCompanion(
            Self.companionSightings(
                list: list, receivedAt: receivedAt, macConnected: macConnected, now: Date(), includes: { filter.contains(ipAddress: $0) },
                profileID: profile?.id, ownLastScan: ownLastScan
            ),
            into: engine.accumulator
        )
    }

    /// An inventory Mac's answers for a scan of `scanned` (#585, #624): only while its inventory is live
    /// for the network the phone is on now (`current`), and `scanned` is that network.
    nonisolated public static func inventoryMacSightings(
        list: DeviceListPayload, receivedAt: Date?, link: CompanionLinkPath?, current: NetworkProfile?, scanned: NetworkProfile,
        gateway: String?, ownLastScan: Date?, now: Date
    ) -> [DiscoveredDevice] {
        guard let receivedAt else { return [] }
        let availability = MacInventory.availability(
            list: list, receivedAt: receivedAt, link: link, phone: current.map { PhoneNetwork(profile: $0, gatewayIP: gateway) },
            viewing: scanned.id, presence: PresenceSnapshot(lastScans: [:], now: now)
        )
        return inventorySightings(list: list, availability: availability, receivedAt: receivedAt, profileID: scanned.id, ownLastScan: ownLastScan)
    }

    /// An inventory Mac's answers as sightings (#585): each interface that answered the Mac's latest
    /// scan, when that scan is newer than the phone's own, only while the inventory is live. They
    /// refresh existing rows (`ScanReconciler.reconcile(_:macSightings:…)`) and never join the scan.
    nonisolated public static func inventorySightings(
        list: DeviceListPayload, availability: MacInventory.Availability, receivedAt: Date, profileID: UUID?, ownLastScan: Date?
    ) -> [DiscoveredDevice] {
        guard case .live(let inventory) = availability, ownLastScan.map({ inventory.scanTime > $0 }) ?? true else { return [] }
        return list.devices.flatMap { device in
            (device.members ?? []).filter(\.answeredLatestScan).map { member in
                let isPrimary = member.isPrimary ?? (device.members?.count == 1)
                return DiscoveredDevice(
                    ipAddress: member.ipAddress, hostname: isPrimary ? device.hostname : nil, vendor: nil,
                    macAddress: (member.macAddress ?? "").isEmpty ? nil : member.macAddress, latency: nil, discoveredAt: receivedAt,
                    source: .macCompanion, networkProfileID: profileID
                )
            }
        }
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
