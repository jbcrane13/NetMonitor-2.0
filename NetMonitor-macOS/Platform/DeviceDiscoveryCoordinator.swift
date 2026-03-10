import Foundation
import SwiftData
import NetMonitorCore
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

    private var scanTask: Task<Void, Never>?

    init(
        modelContext: ModelContext,
        arpScanner: ARPScannerService,
        bonjourScanner: BonjourDiscoveryService,
        nameResolver: DeviceNameResolver = DeviceNameResolver(),
        macVendorService: MACVendorLookupService = MACVendorLookupService(),
        networkProfileManager: NetworkProfileManager
    ) {
        self.modelContext = modelContext
        self.arpScanner = arpScanner
        self.bonjourScanner = bonjourScanner
        self.nameResolver = nameResolver
        self.macVendorService = macVendorService
        self.networkProfileManager = networkProfileManager
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

        scanTask = Task {
            do {
                try Task.checkCancellation()

                scanProgress = 0.1
                let arpDevices = try await arpScanner.scanNetwork(interface: selectedInterface)
                try Task.checkCancellation()
                scanProgress = 0.6

                var bonjourDevices: [LocalDiscoveredDevice] = []
                let bonjourStream = await bonjourScanner.discoveryStream(serviceType: nil)
                let bonjourTask = Task {
                    for await service in bonjourStream {
                        if let host = service.hostName {
                            bonjourDevices.append(LocalDiscoveredDevice(
                                ipAddress: service.addresses.first ?? host,
                                macAddress: "",
                                hostname: host
                            ))
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(5))
                bonjourTask.cancel()
                await bonjourScanner.stopDiscovery()

                try Task.checkCancellation()
                scanProgress = 0.9

                let allDiscovered = mergeDiscoveryResults(arp: arpDevices, bonjour: bonjourDevices)
                mergeDiscoveredDevices(allDiscovered, profileID: profileID)

                try Task.checkCancellation()
                scanProgress = 0.92
                await resolveDeviceNames(profileID: profileID)

                try Task.checkCancellation()
                scanProgress = 0.94
                await resolveDeviceVendors(profileID: profileID)

                try Task.checkCancellation()
                scanProgress = 0.96
                await quickPortScan(profileID: profileID)

                inferDeviceTypes(profileID: profileID)

                try Task.checkCancellation()
                scanProgress = 0.98
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
            isScanning = false
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
        Task {
            await arpScanner.stopScan()
            await bonjourScanner.stopDiscovery()
        }
        isScanning = false
    }

    func mergeDiscoveredDevices(_ devices: [LocalDiscoveredDevice], profileID: UUID?) {
        for discovered in devices {
            let predicate: Predicate<LocalDevice>
            if !discovered.macAddress.isEmpty {
                let mac = discovered.macAddress
                if let profileID {
                    predicate = #Predicate<LocalDevice> { $0.networkProfileID == profileID && $0.macAddress == mac }
                } else {
                    predicate = #Predicate<LocalDevice> { $0.networkProfileID == nil && $0.macAddress == mac }
                }
            } else {
                let ip = discovered.ipAddress
                if let profileID {
                    predicate = #Predicate<LocalDevice> { $0.networkProfileID == profileID && $0.ipAddress == ip }
                } else {
                    predicate = #Predicate<LocalDevice> { $0.networkProfileID == nil && $0.ipAddress == ip }
                }
            }

            let descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
            let existing = try? modelContext.fetch(descriptor).first

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
    private func measureDeviceLatencies(profileID: UUID?) async {
        let devices = fetchDevices(for: profileID).filter { $0.status == .online }
        guard !devices.isEmpty else { return }

        await withTaskGroup(of: (String, Double?).self) { group in
            for device in devices {
                let ip = device.ipAddress
                group.addTask {
                    let pingService = ShellPingService()
                    let result = try? await pingService.ping(host: ip, count: 3, timeout: 2)
                    let latency = result?.isReachable == true ? result?.minLatency : nil
                    return (ip, latency)
                }
            }

            for await (ip, latency) in group {
                if let latency, let device = devices.first(where: { $0.ipAddress == ip }) {
                    device.updateLatency(latency)
                }
            }
        }

        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save device latencies: \(error)")
        }
        loadPersistedDevices(for: profileID)
    }

    private func resolveDeviceNames(profileID: UUID?) async {
        let devices = fetchDevices(for: profileID).filter { $0.hostname == nil || $0.hostname == "" }
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
            !$0.macAddress.isEmpty && ($0.vendor == nil || $0.vendor == "")
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

    /// Quick port scan of common ports for all online devices.
    /// Uses 1s timeout per port, 10 concurrent devices at a time.
    private func quickPortScan(profileID: UUID?) async {
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
                                let isOpen = await Self.checkPort(host: ip, port: port, timeoutMs: 1000)
                                return (port, isOpen)
                            }
                        }
                        for await (port, isOpen) in portGroup {
                            if isOpen { openPorts.append(port) }
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
                                    let isOpen = await Self.checkPort(host: ip, port: port, timeoutMs: 1000)
                                    return (port, isOpen)
                                }
                            }
                            for await (port, isOpen) in portGroup {
                                if isOpen { openPorts.append(port) }
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

    /// Non-blocking TCP connect check with configurable timeout.
    private static func checkPort(host: String, port: Int, timeoutMs: Int32) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue(label: "com.netmonitor.quickportscan").async {
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

    private func mergeDiscoveryResults(
        arp: [LocalDiscoveredDevice],
        bonjour: [LocalDiscoveredDevice]
    ) -> [LocalDiscoveredDevice] {
        var merged: [String: LocalDiscoveredDevice] = [:]
        for d in arp { merged[d.ipAddress] = d }
        for d in bonjour {
            if let existing = merged[d.ipAddress] {
                if existing.hostname == nil, d.hostname != nil {
                    merged[d.ipAddress] = LocalDiscoveredDevice(
                        ipAddress: existing.ipAddress,
                        macAddress: existing.macAddress,
                        hostname: d.hostname
                    )
                }
            } else {
                merged[d.ipAddress] = d
            }
        }
        return Array(merged.values)
    }

    private func effectiveProfileID() -> UUID? {
        networkProfile?.id ?? networkProfileManager.activeProfile?.id
    }
}
