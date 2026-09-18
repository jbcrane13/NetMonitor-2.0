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
    private let arpScanner: ARPScannerService
    let bonjourScanner: BonjourDiscoveryService
    private let nameResolver: DeviceNameResolver
    private let macVendorService: MACVendorLookupService
    let networkProfileManager: NetworkProfileManager

    /// Builds the `ScanEngine` pipeline for a scan. Defaulted to the production
    /// `ScanPipeline.standard` so the nine existing construction sites compile
    /// untouched; tests inject a fixture pipeline for deterministic runs (D16).
    private let pipelineFactory: @Sendable (
        _ bonjourServiceProvider: @escaping @Sendable () async -> [BonjourServiceInfo],
        _ bonjourStopProvider: @escaping @Sendable () async -> Void
    ) -> ScanPipeline

    /// Checks whether `host:port` is reachable. Defaulted to the real raw-socket
    /// `checkPort`; tests inject a no-op checker for deterministic runs (D16).
    private let portChecker: @Sendable (_ host: String, _ port: Int, _ timeoutMs: Int32) async -> Bool

    private var scanTask: Task<Void, Never>?

    /// Matches iOS `DeviceDiscoveryService.maxHostsPerScan` — a bound on how many
    /// addresses `hostAddresses(limit:)` enumerates for very large subnets.
    private static let maxHostsPerScan = 1024

    init(
        modelContext: ModelContext,
        arpScanner: ARPScannerService,
        bonjourScanner: BonjourDiscoveryService,
        nameResolver: DeviceNameResolver = DeviceNameResolver(),
        macVendorService: MACVendorLookupService = MACVendorLookupService(),
        networkProfileManager: NetworkProfileManager,
        pipelineFactory: @escaping @Sendable (
            _ bonjourServiceProvider: @escaping @Sendable () async -> [BonjourServiceInfo],
            _ bonjourStopProvider: @escaping @Sendable () async -> Void
        ) -> ScanPipeline = { ScanPipeline.standard(bonjourServiceProvider: $0, bonjourStopProvider: $1) },
        portChecker: @escaping @Sendable (_ host: String, _ port: Int, _ timeoutMs: Int32) async -> Bool = DeviceDiscoveryCoordinator.checkPort
    ) {
        self.modelContext = modelContext
        self.arpScanner = arpScanner
        self.bonjourScanner = bonjourScanner
        self.nameResolver = nameResolver
        self.macVendorService = macVendorService
        self.networkProfileManager = networkProfileManager
        self.pipelineFactory = pipelineFactory
        self.portChecker = portChecker
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
        let pipeline = pipelineFactory(bonjourProvider, bonjourStop)
        let portChecker = self.portChecker

        scanTask = Task {
            defer { isScanning = false }
            do {
                try Task.checkCancellation()

                bonjourScannerRef.startDiscovery()
                defer { bonjourScannerRef.stopDiscovery() }

                let engine = ScanEngine()
                let engineDevices = await engine.scan(pipeline: pipeline, context: context) { [weak self] progress, _ in
                    await MainActor.run {
                        guard let self else { return }
                        self.scanProgress = min(progress, 1.0) * 0.8
                    }
                }

                try Task.checkCancellation()

                let allDiscovered = Self.mapDiscoveredDevices(engineDevices)

                scanProgress = 0.8
                mergeDiscoveredDevices(allDiscovered, profileID: profileID)

                try Task.checkCancellation()
                scanProgress = 0.84
                await resolveDeviceNames(profileID: profileID)

                try Task.checkCancellation()
                scanProgress = 0.88
                await resolveDeviceVendors(profileID: profileID)

                try Task.checkCancellation()
                scanProgress = 0.92
                await quickPortScan(profileID: profileID, portChecker: portChecker)

                inferDeviceTypes(profileID: profileID)

                try Task.checkCancellation()
                scanProgress = 0.96
                await measureDeviceLatencies(profileID: profileID)

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

    func mergeDiscoveredDevices(_ devices: [LocalDiscoveredDevice], profileID: UUID?) {
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
                existing.lastSeen = Date()
                existing.status = .online
            } else {
                let newDevice = LocalDevice(
                    ipAddress: discovered.ipAddress,
                    macAddress: discovered.macAddress,
                    hostname: discovered.hostname,
                    vendor: nil,
                    deviceType: .unknown,
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

    /// Ping each online device (3 probes, 2s timeout) and store best latency.
    /// Uses ShellPingService (/sbin/ping) which works within the sandbox via shell,
    /// unlike ICMPSocket which requires a raw socket entitlement we don't have.
    ///
    /// Sliding-window cap (matches `resolveDeviceNames` below) — without this we
    /// fork one `/sbin/ping` subprocess per online device, which spikes CPU and
    /// trips thermal throttling on 200+ device networks. See #195.
    ///
    /// Retained per D14: the `ScanEngine`'s `ICMPLatencyPhase` needs a raw-socket
    /// entitlement the sandboxed macOS app does not have and may skip silently, so
    /// shell ping remains the macOS latency source of record (ADR-macOS-003) and
    /// overwrites whatever latency the accumulator supplied.
    private func measureDeviceLatencies(profileID: UUID?) async {
        let devices = fetchDevices(for: profileID).filter { $0.status == .online }
        guard !devices.isEmpty else { return }

        let concurrencyLimit = ThermalThrottleMonitor.shared.effectiveLimit(from: 10)

        await withTaskGroup(of: (String, Double?).self) { group in
            var activeCount = 0
            var iter = devices.makeIterator()

            while activeCount < concurrencyLimit, let device = iter.next() {
                let ip = device.ipAddress
                group.addTask {
                    let pingService = ShellPingService()
                    let result = try? await pingService.ping(host: ip, count: 3, timeout: 2)
                    let latency = result?.isReachable == true ? result?.minLatency : nil
                    return (ip, latency)
                }
                activeCount += 1
            }

            for await (ip, latency) in group {
                if let latency, let device = devices.first(where: { $0.ipAddress == ip }) {
                    device.updateLatency(latency)
                }
                if let next = iter.next() {
                    let nextIP = next.ipAddress
                    group.addTask {
                        let pingService = ShellPingService()
                        let result = try? await pingService.ping(host: nextIP, count: 3, timeout: 2)
                        let latency = result?.isReachable == true ? result?.minLatency : nil
                        return (nextIP, latency)
                    }
                }
            }
        }

        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save device latencies: \(error)")
        }
        loadPersistedDevices(for: profileID)
    }

    private func resolveDeviceNames(profileID: UUID?) async {
        let devices = fetchDevices(for: profileID).filter { $0.hostname == nil || $0.hostname?.isEmpty == true }
        guard !devices.isEmpty else { return }

        await withTaskGroup(of: (UUID, String?).self) { group in
            var activeCount = 0
            var iter = devices.makeIterator()

            while activeCount < 10, let device = iter.next() {
                let id = device.id
                let ip = device.ipAddress
                group.addTask { await (id, self.nameResolver.resolveName(for: ip)) }
                activeCount += 1
            }

            for await (id, name) in group {
                if let name, let device = devices.first(where: { $0.id == id }) {
                    device.hostname = name
                }
                if let next = iter.next() {
                    let id = next.id
                    let ip = next.ipAddress
                    group.addTask { await (id, self.nameResolver.resolveName(for: ip)) }
                }
            }
        }

        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save device names: \(error)")
        }
    }

    private func resolveDeviceVendors(profileID: UUID?) async {
        let devices = fetchDevices(for: profileID).filter {
            !$0.macAddress.isEmpty && ($0.vendor == nil || $0.vendor?.isEmpty == true)
        }
        guard !devices.isEmpty else { return }

        await withTaskGroup(of: (UUID, String?).self) { group in
            var activeCount = 0
            var iter = devices.makeIterator()

            while activeCount < 5, let device = iter.next() {
                let id = device.id
                let mac = device.macAddress
                group.addTask { await (id, self.macVendorService.lookupVendorEnhanced(macAddress: mac)) }
                activeCount += 1
            }

            for await (id, vendor) in group {
                if let vendor, let device = devices.first(where: { $0.id == id }) {
                    device.vendor = vendor
                }
                if let next = iter.next() {
                    let id = next.id
                    let mac = next.macAddress
                    group.addTask { await (id, self.macVendorService.lookupVendorEnhanced(macAddress: mac)) }
                }
            }
        }

        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save device vendors: \(error)")
        }
    }

    /// Performs a quick scan of common ports on online devices for the given profile.
    /// Uses a 1-second timeout per port and scans 10 concurrent devices at a time.
    private func quickPortScan(
        profileID: UUID?,
        portChecker: @escaping @Sendable (_ host: String, _ port: Int, _ timeoutMs: Int32) async -> Bool
    ) async {
        let devices = fetchDevices(for: profileID).filter { $0.status == .online }
        guard !devices.isEmpty else { return }

        // Top common ports — fast fingerprinting set
        let commonPorts = [22, 53, 80, 443, 445, 548, 631, 3389, 5900, 8080, 8443, 8008, 9100, 32400, 62078]

        await withTaskGroup(of: (UUID, [Int]).self) { group in
            var activeCount = 0
            var iter = devices.makeIterator()

            // Limit concurrency to 10 devices at a time
            while activeCount < 10, let device = iter.next() {
                let id = device.id
                let ip = device.ipAddress
                group.addTask {
                    var openPorts: [Int] = []
                    await withTaskGroup(of: (Int, Bool).self) { portGroup in
                        for port in commonPorts {
                            portGroup.addTask {
                                let isOpen = await portChecker(ip, port, 1000)
                                return (port, isOpen)
                            }
                        }
                        for await (port, isOpen) in portGroup where isOpen {
                            openPorts.append(port)
                        }
                    }
                    return (id, openPorts.sorted())
                }
                activeCount += 1
            }

            for await (id, openPorts) in group {
                if let device = devices.first(where: { $0.id == id }) {
                    let existing = Set(device.openPorts ?? [])
                    let combined = existing.union(openPorts).sorted()
                    if !combined.isEmpty {
                        device.openPorts = combined
                    }
                }
                if let next = iter.next() {
                    let id = next.id
                    let ip = next.ipAddress
                    group.addTask {
                        var openPorts: [Int] = []
                        await withTaskGroup(of: (Int, Bool).self) { portGroup in
                            for port in commonPorts {
                                portGroup.addTask {
                                    let isOpen = await portChecker(ip, port, 1000)
                                    return (port, isOpen)
                                }
                            }
                            for await (port, isOpen) in portGroup where isOpen {
                                openPorts.append(port)
                            }
                        }
                        return (id, openPorts.sorted())
                    }
                }
            }
        }

        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save port scan results: \(error)")
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
    /// by `mergeDiscoveredDevices`. `nonisolated` and `static` so tests (and the D16
    /// equivalence test in particular) can call it without any coordinator instance.
    nonisolated static func mapDiscoveredDevices(_ devices: [DiscoveredDevice]) -> [LocalDiscoveredDevice] {
        devices.map { device in
            LocalDiscoveredDevice(
                ipAddress: device.ipAddress,
                macAddress: device.macAddress ?? "",
                hostname: device.hostname
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
        // interface the same way `ARPScannerService.getLocalNetworkInfo` does rather than
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
