import Foundation
import Network

/// Actor-based ARP scanner for discovering devices on the local network
actor ARPScannerService: LocalDeviceScanner {

    // MARK: - Properties

    /// Per-IP probe timeout in seconds (default 1.0)
    let timeout: TimeInterval
    private(set) var isScanning: Bool = false
    private var scanTask: Task<[LocalDiscoveredDevice], Error>?

    // MARK: - Initialization

    init(timeout: TimeInterval = 1.0) {
        self.timeout = timeout
    }

    // MARK: - DeviceDiscoveryService

    func scanNetwork(interface: String? = nil) async throws -> [LocalDiscoveredDevice] {
        guard !isScanning else {
            throw LocalDeviceDiscoveryError.networkUnavailable
        }

        isScanning = true
        defer { isScanning = false }

        // Get local network info
        guard let networkInfo = getLocalNetworkInfo(preferredInterface: interface) else {
            throw LocalDeviceDiscoveryError.networkUnavailable
        }

        let baseIP = calculateBaseIP(ip: networkInfo.ip, mask: networkInfo.subnetMask)
        let ipRange = Self.calculateIPRange(baseIP: baseIP, subnetMask: networkInfo.subnetMask)

        if ipRange.isEmpty {
            throw LocalDeviceDiscoveryError.invalidSubnet
        }

        // Create scan task
        let task = Task<[LocalDiscoveredDevice], Error> {
            var discoveredDevices: [LocalDiscoveredDevice] = []

            // Scan IPs concurrently using a task group with throttling
            let maxConcurrent = 50
            await withTaskGroup(of: LocalDiscoveredDevice?.self) { group in
                var pendingIPs = ipRange.makeIterator()
                var activeCount = 0

                // Seed initial batch
                while activeCount < maxConcurrent, let ip = pendingIPs.next() {
                    group.addTask {
                        // Probe the IP
                        let isReachable = await self.probeIP(ip)

                        if isReachable {
                            // Try to get MAC from ARP cache
                            if let mac = await self.getMACFromARPCache(ip: ip) {
                                return LocalDiscoveredDevice(
                                    ipAddress: ip,
                                    macAddress: mac,
                                    hostname: nil
                                )
                            }
                        }
                        return nil
                    }
                    activeCount += 1
                }

                // As each completes, launch next
                for await result in group {
                    if let device = result {
                        discoveredDevices.append(device)
                    }

                    // Launch next task if available
                    if let ip = pendingIPs.next() {
                        group.addTask {
                            let isReachable = await self.probeIP(ip)

                            if isReachable {
                                if let mac = await self.getMACFromARPCache(ip: ip) {
                                    return LocalDiscoveredDevice(
                                        ipAddress: ip,
                                        macAddress: mac,
                                        hostname: nil
                                    )
                                }
                            }
                            return nil
                        }
                    }
                }
            }

            return discoveredDevices
        }

        scanTask = task

        do {
            return try await task.value
        } catch {
            scanTask = nil
            throw error
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: - Static Methods

    /// Calculate IP range for a given base IP and subnet mask
    /// - Parameters:
    ///   - baseIP: The network base IP address (e.g., "192.168.1.0")
    ///   - subnetMask: The subnet mask (e.g., "255.255.255.0")
    /// - Returns: Array of IP addresses to scan (.1 to .254 for /24)
    static func calculateIPRange(baseIP: String, subnetMask: String) -> [String] {
        // Validate inputs
        guard let baseComponents = parseIP(baseIP),
              let maskComponents = parseIP(subnetMask) else {
            return []
        }

        // For simplicity and performance, limit to /24 equivalent (254 hosts max)
        // This handles both /24 and larger subnets reasonably
        let maxHosts = 254

        // Calculate the last octet range based on subnet mask
        let lastMaskOctet = maskComponents[3]

        // For /24 (255.255.255.0), hosts range from .1 to .254
        // For larger subnets, we still limit to 254 hosts starting from base+1
        let hostBits = 256 - lastMaskOctet

        // If mask is not /24 or larger, limit scan
        guard hostBits >= 2 else {
            return []
        }

        let hostCount = min(hostBits - 2, maxHosts) // -2 for network and broadcast

        var ipRange: [String] = []
        ipRange.reserveCapacity(hostCount)

        let baseOctets = baseComponents

        for i in 1...hostCount {
            // Calculate the IP by adding to the base
            var octets = baseOctets
            var carry = i

            for j in stride(from: 3, through: 0, by: -1) {
                let sum = octets[j] + carry
                octets[j] = sum % 256
                carry = sum / 256
                if carry == 0 { break }
            }

            let ip = "\(octets[0]).\(octets[1]).\(octets[2]).\(octets[3])"
            ipRange.append(ip)
        }

        return ipRange
    }

    // MARK: - Private Methods

    /// Parse an IP address string into its octets
    private static func parseIP(_ ip: String) -> [Int]? {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4,
              parts.allSatisfy({ $0 >= 0 && $0 <= 255 }) else {
            return nil
        }
        return parts
    }

    /// Network info structure
    private struct NetworkInfo {
        let ip: String
        let subnetMask: String
    }

    /// Get local network information using getifaddrs
    private func getLocalNetworkInfo(preferredInterface: String? = nil) -> NetworkInfo? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        var localIP: String?
        var subnetMask: String?

        let targetInterfaces: Set<String>
        if let preferred = preferredInterface {
            targetInterfaces = [preferred]
        } else {
            targetInterfaces = ["en0", "en1"]
        }

        var current = firstAddr
        while true {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)

            // Check for IPv4 interface
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)

                if targetInterfaces.contains(name) {
                    // Check if interface is up and running
                    if (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0 {
                        // Get IP address
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(
                            interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        ) == 0 {
                            localIP = hostname.withUnsafeBufferPointer { buffer in
                                String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                            }
                        }

                        // Get subnet mask
                        if let netmask = interface.ifa_netmask {
                            var maskHostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                            if getnameinfo(
                                netmask,
                                socklen_t(netmask.pointee.sa_len),
                                &maskHostname,
                                socklen_t(maskHostname.count),
                                nil,
                                0,
                                NI_NUMERICHOST
                            ) == 0 {
                                subnetMask = maskHostname.withUnsafeBufferPointer { buffer in
                                    String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                                }
                            }
                        }

                        if localIP != nil && subnetMask != nil {
                            break
                        }
                    }
                }
            }

            guard let next = interface.ifa_next else { break }
            current = next
        }

        guard let ip = localIP, let mask = subnetMask else {
            return nil
        }

        return NetworkInfo(ip: ip, subnetMask: mask)
    }

    /// Calculate the base network IP from an IP and subnet mask
    private func calculateBaseIP(ip: String, mask: String) -> String {
        guard let ipOctets = Self.parseIP(ip),
              let maskOctets = Self.parseIP(mask) else {
            return ip
        }

        let baseOctets = zip(ipOctets, maskOctets).map { $0 & $1 }
        return "\(baseOctets[0]).\(baseOctets[1]).\(baseOctets[2]).\(baseOctets[3])"
    }

    /// Probe a single IP address using NWConnection
    private func probeIP(_ ip: String) async -> Bool {
        let host = NWEndpoint.Host(ip)
        let port = NWEndpoint.Port(integerLiteral: 80)

        let connection = NWConnection(host: host, port: port, using: .tcp)

        let tracker = ContinuationTracker()
        let probeTimeout = self.timeout

        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.netmonitor.arpscanner.\(ip)")

            connection.stateUpdateHandler = { [tracker] state in
                switch state {
                case .ready:
                    if tracker.tryResume() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    if tracker.tryResume() {
                        continuation.resume(returning: false)
                    }
                case .waiting:
                    // Still trying - might be blocked by firewall but host exists
                    // We'll let the timeout handle this
                    break
                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout using the configured timeout value
            queue.asyncAfter(deadline: .now() + probeTimeout) { [tracker] in
                if tracker.tryResume() {
                    connection.cancel()
                    // Even if connection times out, the ARP cache might have been populated
                    continuation.resume(returning: true)
                }
            }
        }
    }

    /// Get MAC address from ARP cache for a given IP
    private func getMACFromARPCache(ip: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", ip]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: nil)
                    return
                }

                // Parse MAC address from ARP output
                // Example output: "192.168.1.1 (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]"
                let pattern = "at ([0-9a-fA-F:]+)"
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(
                        in: output,
                        range: NSRange(output.startIndex..., in: output)
                      ),
                      let macRange = Range(match.range(at: 1), in: output) else {
                    continuation.resume(returning: nil)
                    return
                }

                let mac = String(output[macRange])

                // Validate MAC address format (skip incomplete entries like "(incomplete)")
                if mac.contains(":") && mac.count >= 11 {
                    continuation.resume(returning: mac)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
