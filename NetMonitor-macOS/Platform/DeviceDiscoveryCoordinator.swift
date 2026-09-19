// swiftlint:disable type_body_length
import Foundation
import SwiftData
import NetMonitorCore
import NetworkScanKit
import Network
import Darwin
import os

@MainActor
@Observable
final class DeviceDiscoveryCoordinator {

    private(set) var isScanning: Bool = false
    private(set) var discoveredDevices: [LocalDevice] = []
    private(set) var lastScanTime: Date?
    private(set) var scanProgress: Double = 0.0
    private(set) var networkProfile: NetworkProfile?

    private let modelContext: ModelContext
    let bonjourScanner: BonjourDiscoveryService
    private let nameResolver: ShellDeviceNameResolver
    private let macVendorService: MACVendorLookupService
    let networkProfileManager: NetworkProfileManager

    /// Builds the `ScanEngine` pipeline for a scan from every dependency a phase might need
    /// (E9). Defaulted to the production `ScanPipeline.standard` (real ARP/Bonjour discovery
    /// plus the macOS enrichment step) so existing construction sites compile untouched;
    /// tests inject a fixture pipeline for deterministic runs.
    private let pipelineFactory: @Sendable (ScanPipelineInputs) -> ScanPipeline

    /// Checks whether `host:port` is reachable. Defaulted to the real raw-socket
    /// `checkPort`; tests inject a no-op checker for deterministic runs. Also the
    /// `QuickPortScanPhase`'s dependency.
    private let portChecker: @Sendable (_ host: String, _ port: Int, _ timeoutMs: Int32) async -> Bool

    /// Pings a host and returns the measured latency, or `nil` if unreachable. Defaulted to
    /// the real shell `/sbin/ping` (3 probes, min latency); tests inject a stub. The
    /// `ShellPingLatencyPhase`'s dependency (ADR-003 fallback, E3).
    private let pingRunner: @Sendable (_ host: String) async -> Double?

    private var scanTask: Task<Void, Never>?

    /// Set once per scan the first time the engine reports progress from one of the four
    /// enrichment phases — gates the single sparse merge at the discovery→enrichment
    /// transition (E2) so progressive display fires exactly once per scan.
    private var didMergeAtEnrichmentTransition = false

    /// Matches iOS `DeviceDiscoveryService.maxHostsPerScan` — a bound on how many
    /// addresses `hostAddresses(limit:)` enumerates for very large subnets.
    private static let maxHostsPerScan = 1024

    /// The phase IDs of the four macOS enrichment phases (E9's `standardEnrichmentStep`).
    /// The engine reports progress from these once they start, which is the
    /// discovery→enrichment transition the sparse merge (E2) fires on.
    private static let enrichmentPhaseIDs: Set<ScanPhaseID> = [
        .shellNameResolution, .vendorLookup, .portScan, .shellPingLatency,
    ]

    init(
        modelContext: ModelContext,
        bonjourScanner: BonjourDiscoveryService,
        nameResolver: ShellDeviceNameResolver = ShellDeviceNameResolver(),
        macVendorService: MACVendorLookupService = MACVendorLookupService(),
        networkProfileManager: NetworkProfileManager,
        pipelineFactory: @escaping @Sendable (ScanPipelineInputs) -> ScanPipeline = { inputs in
            ScanPipeline.standard(
                bonjourServiceProvider: inputs.bonjourServiceProvider,
                bonjourStopProvider: inputs.bonjourStopProvider,
                // macOS keeps the shell ping's min-of-3 semantics (E3): 3 ICMP echoes per
                // host instead of iOS's default 1.
                latencyPhase: ICMPLatencyPhase(probeCount: 3),
                trailingSteps: [inputs.standardEnrichmentStep]
            )
        },
        portChecker: @escaping @Sendable (_ host: String, _ port: Int, _ timeoutMs: Int32) async -> Bool = DeviceDiscoveryCoordinator.checkPort,
        pingRunner: @escaping @Sendable (_ host: String) async -> Double? = DeviceDiscoveryCoordinator.shellPing
    ) {
        self.modelContext = modelContext
        self.bonjourScanner = bonjourScanner
        self.nameResolver = nameResolver
        self.macVendorService = macVendorService
        self.networkProfileManager = networkProfileManager
        self.pipelineFactory = pipelineFactory
        self.portChecker = portChecker
        self.pingRunner = pingRunner
        self.networkProfile = networkProfileManager.activeProfile
        loadPersistedDevices(for: effectiveProfileID())
    }

    var selectedInterface: String? {
        networkProfile?.interfaceName
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0
        didMergeAtEnrichmentTransition = false

        let profileID = effectiveProfileID()
        loadPersistedDevices(for: profileID)

        let context = makeScanContext()
        let bonjourScannerRef = bonjourScanner
        let bonjourProvider: @Sendable () async -> [BonjourServiceInfo] = {
            await MainActor.run {
                bonjourScannerRef.discoveredServices.map {
                    BonjourServiceInfo(name: $0.name, type: $0.type, domain: $0.domain)
                }
            }
        }
        let bonjourStop: @Sendable () async -> Void = {
            await MainActor.run { bonjourScannerRef.stopDiscovery() }
        }
        let nameResolverRef = nameResolver
        let inputs = ScanPipelineInputs(
            bonjourServiceProvider: bonjourProvider,
            bonjourStopProvider: bonjourStop,
            nameResolver: { ip in await nameResolverRef.resolveName(for: ip) },
            macVendorService: macVendorService,
            portChecker: portChecker,
            pingRunner: pingRunner
        )
        let pipeline = pipelineFactory(inputs)

        scanTask = Task {
            defer { isScanning = false }
            do {
                try Task.checkCancellation()

                bonjourScannerRef.startDiscovery()
                defer { bonjourScannerRef.stopDiscovery() }

                let engine = ScanEngine()
                let accumulatorRef = engine.accumulator
                let enrichmentPhaseIDs = Self.enrichmentPhaseIDs
                let engineDevices = await engine.scan(pipeline: pipeline, context: context) { [weak self] progress, phaseID in
                    guard let self else { return }
                    await self.handleScanProgress(
                        progress,
                        phaseID: phaseID,
                        profileID: profileID,
                        accumulator: accumulatorRef,
                        enrichmentPhaseIDs: enrichmentPhaseIDs
                    )
                }

                // Partial results on cancellation must not drive a final merge / offline
                // pass — that would flip devices this scan simply didn't get to yet.
                try Task.checkCancellation()

                let allDiscovered = Self.mapDiscoveredDevices(engineDevices)
                mergeDiscoveredDevices(allDiscovered, profileID: profileID, recordLatencyHistory: true)

                inferDeviceTypes(profileID: profileID)

                markOfflineDevices(currentIPs: Set(allDiscovered.map(\.ipAddress)), profileID: profileID)
                scanProgress = 1.0
                lastScanTime = Date()

                if let profileID {
                    let gatewayIP = networkProfile?.gatewayIP
                        ?? networkProfileManager.profiles.first(where: { $0.id == profileID })?.gatewayIP
                    let gatewayReachable = gatewayIP.map { gateway in
                        allDiscovered.contains(where: { $0.ipAddress == gateway })
                    }
                    networkProfileManager.updateProfileScanInfo(
                        id: profileID,
                        lastScanned: Date(),
                        deviceCount: discoveredDevices.count,
                        gatewayReachable: gatewayReachable
                    )
                }
            } catch is CancellationError {
            } catch {
                Logger.discovery.error("Scan error: \(error, privacy: .public)")
            }
        }
    }

    /// Handles one `ScanEngine` progress callback: updates `scanProgress` (E10 — the engine
    /// now drives the whole 0...1 bar, no `* 0.8` scaling) and, the first time a phase from
    /// the enrichment step reports progress, performs the sparse merge (E2) that keeps
    /// progressive display working now that macOS enrichment runs inside the engine instead
    /// of as post-scan `@MainActor` passes.
    ///
    /// The guard-and-set on `didMergeAtEnrichmentTransition` happens before any `await`, so
    /// concurrent calls from the four enrichment phases (which all start together) cannot
    /// race past it: this method is `@MainActor`-isolated, so calls are serialized, and the
    /// synchronous prefix of the first call to arrive completes before any other call's
    /// synchronous prefix can run.
    private func handleScanProgress(
        _ progress: Double,
        phaseID: ScanPhaseID,
        profileID: UUID?,
        accumulator: ScanAccumulator,
        enrichmentPhaseIDs: Set<ScanPhaseID>
    ) async {
        scanProgress = min(progress, 1.0)

        guard !didMergeAtEnrichmentTransition, enrichmentPhaseIDs.contains(phaseID) else { return }
        didMergeAtEnrichmentTransition = true

        let snapshot = await accumulator.sortedSnapshot()
        let sparse = Self.mapDiscoveredDevices(snapshot)
        mergeDiscoveredDevices(sparse, profileID: profileID, recordLatencyHistory: false)
    }

    func scanNetwork(_ profile: NetworkProfile) {
        networkProfile = profile
        _ = networkProfileManager.switchProfile(id: profile.id)
        loadPersistedDevices(for: profile.id)
        startScan()
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        bonjourScanner.stopDiscovery()
        isScanning = false
    }

    /// Merges freshly-discovered devices into persisted `LocalDevice` rows.
    ///
    /// `vendor`/`openPorts`/`latency` are written only when non-nil (E7), so a sparse
    /// pre-enrichment merge can never clear a value a later merge would supply.
    /// `openPorts` unions with whatever was already persisted rather than replacing it —
    /// each scan's quick port check only samples 15 ports, so a port seen open in an earlier
    /// scan but not probed (or momentarily closed) this time shouldn't disappear.
    ///
    /// `recordLatencyHistory` controls whether a non-nil `latency` is written via
    /// `LocalDevice.updateLatency` (which appends to the in-memory sparkline buffer) or set
    /// directly on `lastLatency`. `startScan()` passes `false` for the sparse merge at the
    /// discovery→enrichment transition (E2) — `ICMPLatencyPhase` already populated latency
    /// by then — and `true` for the final merge, so `latencyHistory` grows by exactly one
    /// point per scan rather than two.
    func mergeDiscoveredDevices(_ devices: [LocalDiscoveredDevice], profileID: UUID?, recordLatencyHistory: Bool = true) {
        let existingDevices = fetchDevices(for: profileID)
        var devicesByMAC: [String: LocalDevice] = [:]
        var devicesByIP: [String: LocalDevice] = [:]
        for device in existingDevices {
            let mac = device.macAddress.uppercased()
            if !mac.isEmpty, devicesByMAC[mac] == nil {
                devicesByMAC[mac] = device
            }
            if devicesByIP[device.ipAddress] == nil {
                devicesByIP[device.ipAddress] = device
            }
        }

        for discovered in devices {
            let normalizedMAC = discovered.macAddress.uppercased()
            let existing = normalizedMAC.isEmpty
                ? devicesByIP[discovered.ipAddress]
                : devicesByMAC[normalizedMAC]

            if let existing {
                existing.ipAddress = discovered.ipAddress
                if let hostname = discovered.hostname, !hostname.isEmpty {
                    existing.hostname = hostname
                }
                if let vendor = discovered.vendor, !vendor.isEmpty {
                    existing.vendor = vendor
                }
                if let openPorts = discovered.openPorts, !openPorts.isEmpty {
                    let combined = Set(existing.openPorts ?? []).union(openPorts).sorted()
                    existing.openPorts = combined
                }
                if let latency = discovered.latency {
                    if recordLatencyHistory {
                        existing.updateLatency(latency)
                    } else {
                        existing.lastLatency = latency
                    }
                }
                existing.lastSeen = Date()
                existing.status = .online
            } else {
                let newDevice = LocalDevice(
                    ipAddress: discovered.ipAddress,
                    macAddress: discovered.macAddress,
                    hostname: discovered.hostname,
                    vendor: discovered.vendor,
                    deviceType: .unknown,
                    lastLatency: discovered.latency,
                    openPorts: discovered.openPorts,
                    networkProfileID: profileID
                )
                modelContext.insert(newDevice)
                devicesByIP[newDevice.ipAddress] = newDevice
                if !normalizedMAC.isEmpty {
                    devicesByMAC[normalizedMAC] = newDevice
                }
            }
        }

        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save discovered devices: \(error)")
        }
        loadPersistedDevices(for: profileID)
    }

    func markOfflineDevices(currentIPs: Set<String>, profileID: UUID?) {
        for device in discoveredDevices {
            if device.networkProfileID != profileID {
                continue
            }
            if !currentIPs.contains(device.ipAddress) {
                device.status = .offline
            }
        }
        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save offline status: \(error)")
        }
        loadPersistedDevices(for: profileID)
    }

    /// Shared concurrent queue for `checkPort` so each TCP probe doesn't allocate a
    /// fresh `DispatchQueue`. Concurrent attribute preserves parallel fan-out across
    /// ports/devices (15 ports x N devices were previously running on N*15 disposable
    /// queues per scan). See #203.
    nonisolated private static let portScanQueue = DispatchQueue(
        label: "com.netmonitor.quickportscan",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Non-blocking TCP connect check with configurable timeout, counted against the
    /// shared `ConnectionBudget` like every other raw-socket / `NWConnection` probe.
    /// `QuickPortScanPhase`'s default `checker`.
    nonisolated private static func checkPort(host: String, port: Int, timeoutMs: Int32) async -> Bool {
        await withConnectionSlot {
            await withCheckedContinuation { continuation in
                portScanQueue.async {
                    var hints = addrinfo()
                    hints.ai_family = AF_INET
                    hints.ai_socktype = SOCK_STREAM
                    hints.ai_protocol = IPPROTO_TCP

                    var result: UnsafeMutablePointer<addrinfo>?
                    let portString = String(port)
                    let resolveStatus = getaddrinfo(host, portString, &hints, &result)

                    guard resolveStatus == 0, let addrInfo = result else {
                        continuation.resume(returning: false)
                        return
                    }
                    defer { freeaddrinfo(result) }

                    let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
                    guard sock >= 0 else {
                        continuation.resume(returning: false)
                        return
                    }
                    defer { close(sock) }

                    // Non-blocking
                    var flags = fcntl(sock, F_GETFL, 0)
                    flags |= O_NONBLOCK
                    _ = fcntl(sock, F_SETFL, flags)

                    _ = connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)

                    if errno == EINPROGRESS {
                        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
                        let pollResult = poll(&pfd, 1, timeoutMs)
                        if pollResult > 0 {
                            var socketError: Int32 = 0
                            var errorLen = socklen_t(MemoryLayout<Int32>.size)
                            getsockopt(sock, SOL_SOCKET, SO_ERROR, &socketError, &errorLen)
                            continuation.resume(returning: socketError == 0)
                        } else {
                            continuation.resume(returning: false)
                        }
                    } else {
                        continuation.resume(returning: errno == 0)
                    }
                }
            }
        } ?? false
    }

    /// Pings `host` (3 probes, 2s timeout each) via `/sbin/ping` and returns the minimum
    /// observed latency, or `nil` if unreachable. `ShellPingLatencyPhase`'s default
    /// `pinger` — the ADR-003 fallback for devices `ICMPLatencyPhase` didn't cover (E3).
    nonisolated static func shellPing(host: String) async -> Double? {
        let pingService = ShellPingService()
        let result = try? await pingService.ping(host: host, count: 3, timeout: 2)
        return result?.isReachable == true ? result?.minLatency : nil
    }

    private func inferDeviceTypes(profileID: UUID?) {
        let inference = DeviceTypeInferenceService()
        let devices = fetchDevices(for: profileID).filter { $0.deviceType == .unknown }
        var changed = false
        for device in devices {
            let inferred = inference.inferDeviceType(for: device)
            if inferred != .unknown {
                device.deviceType = inferred
                changed = true
            }
        }
        if changed {
            do { try modelContext.save() } catch {
                Logger.discovery.error("Failed to save inferred device types: \(error)")
            }
            loadPersistedDevices(for: profileID)
        }
    }

    private func loadPersistedDevices(for profileID: UUID?) {
        let devices = fetchDevices(for: profileID)
        discoveredDevices = devices.sorted { $0.lastSeen > $1.lastSeen }
    }

    private func fetchDevices(for profileID: UUID?) -> [LocalDevice] {
        let descriptor: FetchDescriptor<LocalDevice>
        if let profileID {
            let predicate = #Predicate<LocalDevice> { $0.networkProfileID == profileID }
            descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
        } else {
            let predicate = #Predicate<LocalDevice> { $0.networkProfileID == nil }
            descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
        }

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Maps `ScanEngine` accumulator results to the macOS-local discovery type consumed
    /// by `mergeDiscoveredDevices`. `nonisolated` and `static` so tests (and the golden-row
    /// equivalence tests in particular) can call it without any coordinator instance.
    nonisolated static func mapDiscoveredDevices(_ devices: [DiscoveredDevice]) -> [LocalDiscoveredDevice] {
        devices.map { device in
            LocalDiscoveredDevice(
                ipAddress: device.ipAddress,
                macAddress: device.macAddress ?? "",
                hostname: device.hostname,
                vendor: device.vendor,
                openPorts: device.openPorts,
                latency: device.latency
            )
        }
    }

    /// Builds the `ScanContext` for a scan, deriving `hosts` and the subnet filter the
    /// way iOS `DeviceDiscoveryService.makeScanTarget(profile:)` / `makeScanTarget(subnet:)`
    /// do — both platforms share `NetworkProfile` and `NetworkUtilities` in NetMonitorCore.
    /// `requiredInterfaceType` is `nil` (any interface): unlike iOS, a wired Mac must still
    /// be able to discover devices (D15).
    private func makeScanContext() -> ScanContext {
        if let profile = networkProfile {
            let hosts = profile.network.hostAddresses(limit: Self.maxHostsPerScan)
            let localIP = NetworkUtilities.detectLocalIPAddress(interface: profile.interfaceName)
            return ScanContext(
                hosts: hosts,
                subnetFilter: { profile.network.contains(ipAddress: $0) },
                localIP: localIP,
                requiredInterfaceType: nil
            )
        }

        // No active profile yet (e.g. first launch before profile detection completes) —
        // fall back the same way iOS `makeScanTarget(subnet: nil)` does, but pick the
        // interface the same way `ARPScannerService.getLocalNetworkInfo` did rather than
        // assuming `NetworkUtilities`'s "en0" default: not every Mac's primary LAN
        // interface is en0 (e.g. en1 when en0 is inactive/unplugged — see #279).
        let interface = Self.selectFallbackInterface()

        if let interface, let network = NetworkUtilities.detectLocalIPv4Network(interface: interface) {
            let hosts = network.hostAddresses(limit: Self.maxHostsPerScan)
            if !hosts.isEmpty {
                return ScanContext(
                    hosts: hosts,
                    subnetFilter: { network.contains(ipAddress: $0) },
                    localIP: NetworkUtilities.detectLocalIPAddress(interface: interface),
                    requiredInterfaceType: nil
                )
            }
        }

        let subnet = interface.flatMap { NetworkUtilities.detectSubnet(interface: $0) } ?? "192.168.1"
        let localIP = interface.flatMap { NetworkUtilities.detectLocalIPAddress(interface: $0) }
            ?? NetworkUtilities.detectLocalIPAddress()
        var hosts: [String] = []
        hosts.reserveCapacity(254)
        for host in 1...254 {
            let ip = "\(subnet).\(host)"
            if ip != localIP {
                hosts.append(ip)
            }
        }
        return ScanContext(
            hosts: hosts,
            subnetFilter: { $0.hasPrefix(subnet + ".") },
            localIP: localIP,
            requiredInterfaceType: nil
        )
    }

    /// BSD interface names probed, in order, when no `NetworkProfile` is active yet.
    /// Widened from `ARPScannerService.getLocalNetworkInfo`'s `["en0", "en1"]` to
    /// `en0...en9` for the same reason: the primary LAN interface isn't always en0.
    nonisolated private static let fallbackInterfaceCandidates: [String] = (0...9).map { "en\($0)" }

    /// Picks the first candidate interface that currently has a live IPv4 network.
    /// `networkProvider` defaults to the real `NetworkUtilities.detectLocalIPv4Network(interface:)`
    /// but is injectable so this selection logic is unit-testable without real interface
    /// syscalls (see `DeviceDiscoveryCoordinatorTests`).
    nonisolated static func selectFallbackInterface(
        candidates: [String] = DeviceDiscoveryCoordinator.fallbackInterfaceCandidates,
        networkProvider: (String) -> NetworkUtilities.IPv4Network? = { NetworkUtilities.detectLocalIPv4Network(interface: $0) }
    ) -> String? {
        candidates.first { networkProvider($0) != nil }
    }

    private func effectiveProfileID() -> UUID? {
        networkProfile?.id ?? networkProfileManager.activeProfile?.id
    }
}

// swiftlint:enable type_body_length
