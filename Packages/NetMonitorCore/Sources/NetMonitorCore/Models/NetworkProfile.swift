import Foundation

/// Represents a network interface with its IPv4 configuration.
///
/// Used by the multi-network scanning feature to let users select which
/// network interface to scan. Each profile maps to a single active IPv4
/// interface (e.g., en0 for Wi-Fi, en1 for Ethernet).
public struct NetworkProfile: Identifiable, Sendable, Hashable {
    /// Unique identifier — the BSD interface name (e.g., "en0").
    public let id: String

    /// BSD interface name (e.g., "en0", "en1").
    public let interfaceName: String

    /// The device's IPv4 address on this interface.
    public let ipAddress: String

    /// Full IPv4 network descriptor (address, netmask, broadcast).
    public let network: NetworkUtilities.IPv4Network

    /// Inferred connection type (Wi-Fi, Ethernet, Cellular).
    public let connectionType: ConnectionType

    /// User-facing label (e.g., "Wi-Fi (192.168.1.0/24)").
    public let displayName: String

    public init(
        interfaceName: String,
        ipAddress: String,
        network: NetworkUtilities.IPv4Network,
        connectionType: ConnectionType,
        displayName: String? = nil
    ) {
        self.id = interfaceName
        self.interfaceName = interfaceName
        self.ipAddress = ipAddress
        self.network = network
        self.connectionType = connectionType
        self.displayName = displayName ?? Self.makeDisplayName(
            interface: interfaceName,
            connectionType: connectionType,
            network: network
        )
    }

    /// Subnet in CIDR notation (e.g., "192.168.1.0/24").
    public var subnetCIDR: String {
        let networkIP = NetworkUtilities.uint32ToIPv4(network.networkAddress)
        return "\(networkIP)/\(network.prefixLength)"
    }

    /// Number of scannable host addresses in this subnet.
    public var hostCount: Int {
        let first = network.networkAddress &+ 1
        let last = network.broadcastAddress &- 1
        guard last >= first else { return 0 }
        return Int(UInt64(last) - UInt64(first) + 1)
    }

    // MARK: - Private

    private static func makeDisplayName(
        interface: String,
        connectionType: ConnectionType,
        network: NetworkUtilities.IPv4Network
    ) -> String {
        let subnet = NetworkUtilities.uint32ToIPv4(network.networkAddress)
        let prefix = network.prefixLength
        let label: String

        switch interface {
        case "en0":
            label = connectionType == .wifi ? "Wi-Fi" : "Ethernet"
        case "en1":
            label = "Ethernet"
        default:
            if interface.hasPrefix("en") {
                label = "Ethernet (\(interface))"
            } else if interface.hasPrefix("utun") || interface.hasPrefix("ipsec") {
                label = "VPN (\(interface))"
            } else if interface.hasPrefix("bridge") {
                label = "Bridge (\(interface))"
            } else if interface.hasPrefix("pdp_ip") {
                label = "Cellular"
            } else {
                label = interface
            }
        }

        return "\(label) — \(subnet)/\(prefix)"
    }
}
