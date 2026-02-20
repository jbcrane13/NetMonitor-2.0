import Foundation

/// Enumerates active IPv4 network interfaces and returns ``NetworkProfile`` instances.
///
/// This is a stateless utility (like ``NetworkUtilities``) — call
/// ``detectActiveProfiles()`` whenever you need a fresh snapshot of available networks.
public enum NetworkProfileManager {

    /// Returns all active IPv4 network interfaces, sorted by priority
    /// (Wi-Fi first, then Ethernet, then others).
    ///
    /// Filters out:
    /// - Loopback (lo0)
    /// - Link-local addresses (169.254.x.x)
    /// - Interfaces that are not UP and RUNNING
    /// - Duplicate interface entries
    public static func detectActiveProfiles() -> [NetworkProfile] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var profiles: [NetworkProfile] = []
        var seen = Set<String>()

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee

            guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: iface.ifa_name)
            guard name != "lo0", !seen.contains(name) else { continue }

            let flags = Int32(iface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 else { continue }

            guard let network = NetworkUtilities.detectLocalIPv4Network(interface: name),
                  let ip = NetworkUtilities.detectLocalIPAddress(interface: name) else { continue }

            // Skip link-local (APIPA) addresses
            guard !ip.hasPrefix("169.254.") else { continue }

            let connectionType = inferConnectionType(for: name)

            profiles.append(NetworkProfile(
                interfaceName: name,
                ipAddress: ip,
                network: network,
                connectionType: connectionType
            ))
            seen.insert(name)
        }

        return profiles.sorted { sortPriority($0) < sortPriority($1) }
    }

    /// Returns the "primary" profile — the first active interface by priority,
    /// or nil if no interfaces are active.
    public static func primaryProfile() -> NetworkProfile? {
        detectActiveProfiles().first
    }

    // MARK: - Private

    private static func inferConnectionType(for interface: String) -> ConnectionType {
        switch interface {
        case "en0":
            return .wifi
        case "en1", "en2", "en3", "en4", "en5":
            return .ethernet
        default:
            if interface.hasPrefix("en") { return .ethernet }
            if interface.hasPrefix("pdp_ip") { return .cellular }
            return .ethernet
        }
    }

    private static func sortPriority(_ profile: NetworkProfile) -> Int {
        switch profile.connectionType {
        case .wifi: return 0
        case .ethernet: return 1
        case .cellular: return 2
        case .none: return 3
        }
    }
}
