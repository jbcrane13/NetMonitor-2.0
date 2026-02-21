import Foundation

public enum DiscoveryMethod: String, Codable, CaseIterable, Sendable {
    case auto
    case manual
    case companion
}

/// Represents a network profile with scanning and persistence metadata.
public struct NetworkProfile: Identifiable, Codable, Sendable, Hashable {
    /// Stable UUID identifier for this profile.
    public let id: UUID

    /// BSD interface name (e.g., "en0", "en1"), when available.
    public var interfaceName: String

    /// IPv4 address associated with this profile.
    public var ipAddress: String

    /// Full IPv4 network descriptor (address, netmask, broadcast).
    public var network: NetworkUtilities.IPv4Network

    /// Inferred connection type (Wi-Fi, Ethernet, Cellular).
    public var connectionType: ConnectionType

    /// User-editable profile label.
    public var name: String

    /// Router/gateway IP for this network.
    public var gatewayIP: String

    /// Network subnet in CIDR notation.
    public var subnet: String

    /// Whether this profile maps to the currently connected local network.
    public var isLocal: Bool

    /// How this profile was discovered.
    public var discoveryMethod: DiscoveryMethod

    /// Timestamp for the last completed scan against this profile.
    public var lastScanned: Date?

    /// Last known device count for this profile.
    public var deviceCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case interfaceName
        case ipAddress
        case network
        case connectionType
        case name
        case gatewayIP
        case subnet
        case isLocal
        case discoveryMethod
        case lastScanned
        case deviceCount
    }

    /// Backward-compatible initializer used by interface enumeration call sites.
    public init(
        interfaceName: String,
        ipAddress: String,
        network: NetworkUtilities.IPv4Network,
        connectionType: ConnectionType,
        displayName: String? = nil
    ) {
        self.id = Self.stableID(for: interfaceName)
        self.interfaceName = interfaceName
        self.ipAddress = ipAddress
        self.network = network
        self.connectionType = connectionType
        self.name = displayName ?? Self.makeDisplayName(
            interface: interfaceName,
            connectionType: connectionType,
            network: network
        )
        self.gatewayIP = NetworkUtilities.uint32ToIPv4(network.networkAddress &+ 1)
        self.subnet = "\(NetworkUtilities.uint32ToIPv4(network.networkAddress))/\(network.prefixLength)"
        self.isLocal = true
        self.discoveryMethod = .auto
        self.lastScanned = nil
        self.deviceCount = nil
    }

    public init(
        id: UUID = UUID(),
        interfaceName: String,
        ipAddress: String,
        network: NetworkUtilities.IPv4Network,
        connectionType: ConnectionType,
        name: String,
        gatewayIP: String,
        subnet: String,
        isLocal: Bool,
        discoveryMethod: DiscoveryMethod,
        lastScanned: Date? = nil,
        deviceCount: Int? = nil
    ) {
        self.id = id
        self.interfaceName = interfaceName
        self.ipAddress = ipAddress
        self.network = network
        self.connectionType = connectionType
        self.name = name
        self.gatewayIP = gatewayIP
        self.subnet = subnet
        self.isLocal = isLocal
        self.discoveryMethod = discoveryMethod
        self.lastScanned = lastScanned
        self.deviceCount = deviceCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyID = try? container.decode(String.self, forKey: .id)

        if let uuid = try? container.decode(UUID.self, forKey: .id) {
            id = uuid
        } else if let legacyID {
            id = Self.stableID(for: legacyID)
        } else {
            id = UUID()
        }

        network = try container.decode(NetworkUtilities.IPv4Network.self, forKey: .network)
        interfaceName = try container.decodeIfPresent(String.self, forKey: .interfaceName) ?? legacyID ?? "en0"
        ipAddress = try container.decodeIfPresent(String.self, forKey: .ipAddress)
            ?? NetworkUtilities.uint32ToIPv4(network.interfaceAddress)
        connectionType = try container.decodeIfPresent(ConnectionType.self, forKey: .connectionType) ?? .ethernet
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? Self.makeDisplayName(
            interface: interfaceName,
            connectionType: connectionType,
            network: network
        )
        gatewayIP = try container.decodeIfPresent(String.self, forKey: .gatewayIP)
            ?? NetworkUtilities.uint32ToIPv4(network.networkAddress &+ 1)
        subnet = try container.decodeIfPresent(String.self, forKey: .subnet)
            ?? "\(NetworkUtilities.uint32ToIPv4(network.networkAddress))/\(network.prefixLength)"
        isLocal = try container.decodeIfPresent(Bool.self, forKey: .isLocal) ?? true
        discoveryMethod = try container.decodeIfPresent(DiscoveryMethod.self, forKey: .discoveryMethod)
            ?? (isLocal ? .auto : .manual)
        lastScanned = try container.decodeIfPresent(Date.self, forKey: .lastScanned)
        deviceCount = try container.decodeIfPresent(Int.self, forKey: .deviceCount)
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

    /// User-facing label used by existing UI call sites.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return Self.makeDisplayName(
            interface: interfaceName,
            connectionType: connectionType,
            network: network
        )
    }

    // MARK: - Private

    static func stableID(for interfaceName: String) -> UUID {
        let bytes = [UInt8](interfaceName.utf8)
        guard !bytes.isEmpty else { return UUID() }

        var digest = [UInt8](repeating: 0, count: 16)
        for (index, byte) in bytes.enumerated() {
            let slot = index % digest.count
            digest[slot] = digest[slot] &+ byte &+ UInt8(index & 0xFF)
        }

        // UUID version (4) and variant bits.
        digest[6] = (digest[6] & 0x0F) | 0x40
        digest[8] = (digest[8] & 0x3F) | 0x80

        let uuid: uuid_t = (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        )
        return UUID(uuid: uuid)
    }

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
