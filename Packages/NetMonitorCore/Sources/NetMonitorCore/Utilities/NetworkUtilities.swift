import Foundation

// MARK: - NetworkUtilities

/// Shared network interface utilities for detecting local IP addresses and subnets.
public enum NetworkUtilities {

    // MARK: - IPv4Network

    public struct IPv4Network: Sendable, Equatable, Hashable {
        public let networkAddress: UInt32
        public let broadcastAddress: UInt32
        public let interfaceAddress: UInt32
        public let netmask: UInt32

        public var prefixLength: Int { netmask.nonzeroBitCount }

        /// Returns whether the given IPv4 address belongs to this network.
        public func contains(ipAddress: String) -> Bool {
            guard let value = NetworkUtilities.ipv4ToUInt32(ipAddress) else { return false }
            return (value & netmask) == networkAddress
        }

        /// Generates host addresses within the network.
        /// For very large subnets, returns a bounded window centered on the interface IP.
        public func hostAddresses(limit: Int, excludingInterface: Bool = true) -> [String] {
            guard limit > 0 else { return [] }
            guard networkAddress < broadcastAddress else { return [] }
            guard broadcastAddress - networkAddress > 1 else { return [] }

            let firstHost = networkAddress &+ 1
            let lastHost = broadcastAddress &- 1
            let totalHosts = Int(UInt64(lastHost) - UInt64(firstHost) + 1)
            let targetCount = min(limit, totalHosts)

            let localHost = min(max(interfaceAddress, firstHost), lastHost)
            var rangeStart = firstHost
            var rangeEnd = lastHost

            if totalHosts > targetCount {
                let halfWindow = UInt32(targetCount / 2)
                rangeStart = localHost > firstHost &+ halfWindow ? localHost &- halfWindow : firstHost
                let maxStart = lastHost &- UInt32(targetCount - 1)
                if rangeStart > maxStart { rangeStart = maxStart }
                rangeEnd = rangeStart &+ UInt32(targetCount - 1)
            }

            var addresses: [String] = []
            addresses.reserveCapacity(targetCount)

            func appendRange(from start: UInt32, to end: UInt32) {
                guard start <= end else { return }
                var current = start
                while current <= end, addresses.count < targetCount {
                    if !(excludingInterface && current == interfaceAddress) {
                        addresses.append(NetworkUtilities.uint32ToIPv4(current))
                    }
                    if current == UInt32.max { break }
                    current &+= 1
                }
            }

            appendRange(from: rangeStart, to: rangeEnd)
            if addresses.count < targetCount, rangeStart > firstHost {
                appendRange(from: firstHost, to: rangeStart &- 1)
            }
            if addresses.count < targetCount, rangeEnd < lastHost {
                appendRange(from: rangeEnd &+ 1, to: lastHost)
            }

            return addresses
        }
    }

    // MARK: - Interface Detection

    /// Detects the local IP address for a given network interface.
    /// - Parameter interface: The interface name (default: "en0" for primary WiFi)
    /// - Returns: The IP address string, or nil if not found
    public static func detectLocalIPAddress(interface: String = "en0") -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard String(cString: iface.ifa_name) == interface else { continue }

            var addr = iface.ifa_addr.pointee
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(&addr, socklen_t(iface.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            let length = strnlen(hostname, hostname.count)
            let bytes = hostname.prefix(length).map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        }
        return nil
    }

    /// Detects the full IPv4 network descriptor for a given interface.
    /// - Parameter interface: The interface name (default: "en0")
    /// - Returns: An `IPv4Network`, or nil if unavailable.
    public static func detectLocalIPv4Network(interface: String = "en0") -> IPv4Network? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard String(cString: iface.ifa_name) == interface else { continue }
            guard let addrPtr = iface.ifa_addr, let netmaskPtr = iface.ifa_netmask else { continue }

            let address = UnsafeRawPointer(addrPtr).assumingMemoryBound(to: sockaddr_in.self).pointee
            let mask = UnsafeRawPointer(netmaskPtr).assumingMemoryBound(to: sockaddr_in.self).pointee

            let interfaceAddress = UInt32(bigEndian: address.sin_addr.s_addr)
            let netmask = UInt32(bigEndian: mask.sin_addr.s_addr)
            let networkAddress = interfaceAddress & netmask
            let broadcastAddress = networkAddress | ~netmask

            return IPv4Network(
                networkAddress: networkAddress,
                broadcastAddress: broadcastAddress,
                interfaceAddress: interfaceAddress,
                netmask: netmask
            )
        }
        return nil
    }

    /// Detects the subnet prefix string (e.g., "192.168.1") for a given interface.
    public static func detectSubnet(interface: String = "en0") -> String? {
        guard let ip = detectLocalIPAddress(interface: interface) else { return nil }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2])"
    }

    /// Detects the default gateway IP (first host on the local subnet).
    public static func detectDefaultGateway(interface: String = "en0") -> String? {
        if let network = detectLocalIPv4Network(interface: interface),
           network.broadcastAddress > network.networkAddress {
            return uint32ToIPv4(network.networkAddress &+ 1)
        }
        guard let subnet = detectSubnet(interface: interface) else { return nil }
        return "\(subnet).1"
    }

    // MARK: - Helpers

    static func ipv4ToUInt32(_ address: String) -> UInt32? {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(octet)
        }
        return value
    }

    public static func uint32ToIPv4(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }
}
