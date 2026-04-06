import Foundation
import NetMonitorCore
import SwiftData
import NetworkScanKit

@MainActor
@Observable
final class DeviceDetailViewModel {
    var device: LocalDevice?
    var isLoading: Bool = false
    var error: String?
    var isScanning: Bool = false
    var isDiscovering: Bool = false

    private let macLookupService: any MACVendorLookupServiceProtocol
    private let nameResolver: any DeviceNameResolverProtocol
    private let portScanner: any PortScannerServiceProtocol
    private let bonjourService: any BonjourDiscoveryServiceProtocol
    private let maxServiceResolves = 80
    private let maxServiceResolveConcurrency = 8

    init(
        macLookupService: any MACVendorLookupServiceProtocol = MACVendorLookupService(),
        nameResolver: any DeviceNameResolverProtocol = DeviceNameResolver(),
        portScanner: any PortScannerServiceProtocol = PortScannerService(),
        bonjourService: any BonjourDiscoveryServiceProtocol = BonjourDiscoveryService()
    ) {
        self.macLookupService = macLookupService
        self.nameResolver = nameResolver
        self.portScanner = portScanner
        self.bonjourService = bonjourService
    }

    // Common ports to scan
    private let commonPorts = [
        21, 22, 23, 25, 53, 80, 110, 143, 443, 445, 548, 631,
        993, 995, 3306, 3389, 5432, 5900, 8080, 8443
    ]

    /// Load device from SwiftData by IP address, creating one if not found
    func loadDevice(ipAddress: String, context: ModelContext) {
        let descriptor = FetchDescriptor<LocalDevice>(
            predicate: #Predicate { $0.ipAddress == ipAddress }
        )
        if let existing = try? context.fetch(descriptor).first {
            device = existing
        } else {
            let newDevice = LocalDevice(
                ipAddress: ipAddress,
                macAddress: ""
            )
            context.insert(newDevice)
            device = newDevice
        }
    }

    /// Enrich device data with manufacturer and resolved hostname
    func enrichDevice(bonjourServices _: [BonjourService]) async {
        guard let device = device else { return }
        isLoading = true
        defer { isLoading = false }

        // Extract Sendable values before async work
        let macAddress = device.macAddress
        let ipAddress = device.ipAddress

        // Lookup manufacturer from MAC address (skip if empty)
        if device.manufacturer == nil, !macAddress.isEmpty {
            let manufacturer: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    await self.macLookupService.lookup(macAddress: macAddress)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    return nil
                }
                let result = await group.next()
                group.cancelAll()
                return result
            }
            if !Task.isCancelled { device.manufacturer = manufacturer }
        }

        guard !Task.isCancelled else { return }

        // Resolve hostname with timeout to prevent hanging on DNS
        if device.resolvedHostname == nil {
            let hostname: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    await self.nameResolver.resolve(ipAddress: ipAddress)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    return nil
                }
                let result = await group.next()
                group.cancelAll()
                return result
            }
            if !Task.isCancelled { device.resolvedHostname = hostname }
        }
    }

    /// Scan common ports on the device
    func scanPorts() async {
        guard let device = device else { return }
        isScanning = true
        defer { isScanning = false }

        var openPorts: [Int] = []

        for await result in await portScanner.scan(host: device.ipAddress, ports: commonPorts, timeout: 1.5) {
            if result.state == .open {
                openPorts.append(result.port)
            }
        }

        device.openPorts = openPorts.sorted()
    }

    /// Discover Bonjour services matching this device's IP
    func discoverServices() async {
        guard let device = device else { return }
        isDiscovering = true
        defer { isDiscovering = false }

        // Phase 1: Collect services from stream (up to 10 seconds)
        var collectedServices: [BonjourService] = []
        let stream = bonjourService.discoveryStream(serviceType: nil)

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(10))
            bonjourService.stopDiscovery()
        }

        for await service in stream {
            collectedServices.append(service)
        }
        timeoutTask.cancel()

        // Phase 2: Resolve and match services (bounded concurrency)
        let deviceIP = device.ipAddress
        var discoveredServiceNames: [String] = []
        let servicesToResolve = Array(uniqueServices(from: collectedServices).prefix(maxServiceResolves))

        await withTaskGroup(of: String?.self) { group in
            var pending = 0
            var iterator = servicesToResolve.makeIterator()

            while pending < maxServiceResolveConcurrency, let service = iterator.next() {
                pending += 1
                group.addTask { [deviceIP] in
                    guard let resolved = await self.bonjourService.resolveService(service),
                          await Self.serviceMatchesDeviceIP(resolved, deviceIP: deviceIP) else {
                        return nil
                    }
                    return "\(service.name) (\(service.type))"
                }
            }

            while pending > 0 {
                guard let name = await group.next() else { break }
                pending -= 1

                if let name, !discoveredServiceNames.contains(name) {
                    discoveredServiceNames.append(name)
                }

                if let nextService = iterator.next() {
                    pending += 1
                    group.addTask { [deviceIP] in
                        guard let resolved = await self.bonjourService.resolveService(nextService),
                              await Self.serviceMatchesDeviceIP(resolved, deviceIP: deviceIP) else {
                            return nil
                        }
                        return "\(nextService.name) (\(nextService.type))"
                    }
                }
            }
        }

        device.discoveredServices = discoveredServiceNames
    }

    private func uniqueServices(from services: [BonjourService]) -> [BonjourService] {
        var seen: Set<String> = []
        var unique: [BonjourService] = []
        unique.reserveCapacity(services.count)

        for service in services {
            let key = "\(service.name)|\(service.type)|\(service.domain)"
            if seen.insert(key).inserted {
                unique.append(service)
            }
        }
        return unique
    }

    nonisolated private static func serviceMatchesDeviceIP(_ resolved: BonjourService, deviceIP: String) async -> Bool {
        var candidates: Set<String> = []

        for address in resolved.addresses where isIPv4Address(address) {
            candidates.insert(address)
        }

        if let hostName = resolved.hostName {
            let normalizedHost = normalizeHostName(hostName)
            if isIPv4Address(normalizedHost) {
                candidates.insert(normalizedHost)
            } else if !normalizedHost.isEmpty {
                let resolvedIPs = await resolveIPv4Addresses(for: normalizedHost)
                for ip in resolvedIPs {
                    candidates.insert(ip)
                }
            }
        }

        return candidates.contains(deviceIP)
    }

    nonisolated private static func normalizeHostName(_ host: String) -> String {
        host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
    }

    nonisolated private static func isIPv4Address(_ value: String) -> Bool {
        ServiceUtilities.isIPv4Address(value)
    }

    nonisolated private static func resolveIPv4Addresses(for host: String) async -> [String] {
        await withCheckedContinuation { continuation in
            let cfHost = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
            var streamError = CFStreamError()

            guard CFHostStartInfoResolution(cfHost, .addresses, &streamError),
                  let addresses = CFHostGetAddressing(cfHost, nil)?.takeUnretainedValue() as? [Data] else {
                continuation.resume(returning: [])
                return
            }

            var resolved: Set<String> = []
            resolved.reserveCapacity(addresses.count)

            for addressData in addresses {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                addressData.withUnsafeBytes { ptr in
                    guard let sockaddr = ptr.bindMemory(to: sockaddr.self).baseAddress else { return }
                    getnameinfo(
                        sockaddr,
                        socklen_t(addressData.count),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                }

                let length = strnlen(hostname, hostname.count)
                let bytes = hostname.prefix(length).map { UInt8(bitPattern: $0) }
                let ip = String(decoding: bytes, as: UTF8.self)

                if isIPv4Address(ip) {
                    resolved.insert(ip)
                }
            }

            continuation.resume(returning: Array(resolved))
        }
    }
}
