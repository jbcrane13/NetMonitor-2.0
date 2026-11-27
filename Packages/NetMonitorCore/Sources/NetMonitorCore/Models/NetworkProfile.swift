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

    /// Last known gateway reachability for this profile.
    public var gatewayReachable: Bool?

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
        case gatewayReachable
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
        self.gatewayReachable = nil
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
        deviceCount: Int? = nil,
        gatewayReachable: Bool? = nil
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
        self.gatewayReachable = gatewayReachable
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
        gatewayReachable = try container.decodeIfPresent(Bool.self, forKey: .gatewayReachable)
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

    /// A name the user gave the network; nil when it has only the generated one, which is the same at
    /// every site on one interface and subnet (#645).
    public var customName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = Self.makeDisplayName(interface: interfaceName, connectionType: connectionType, network: network)
        return trimmed.isEmpty || trimmed == generated ? nil : trimmed
    }

    /// User-facing label used by existing UI call sites.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return Self.makeDisplayName(
            interface: interfaceName,
            connectionType: connectionType,
            network: network
        )
    }

    /// The same profile under another id. `id` is a `let`, so changing it means a copy.
    func withID(_ newID: UUID) -> NetworkProfile {
        NetworkProfile(
            id: newID,
            interfaceName: interfaceName,
            ipAddress: ipAddress,
            network: network,
            connectionType: connectionType,
            name: name,
            gatewayIP: gatewayIP,
            subnet: subnet,
            isLocal: isLocal,
            discoveryMethod: discoveryMethod,
            lastScanned: lastScanned,
            deviceCount: deviceCount,
            gatewayReachable: gatewayReachable
        )
    }

    /// Deterministic id for a detected network that can't use its interface's `stableID`,
    /// because another network on that interface already has it. Two 64-bit FNV-1a hashes
    /// with different offsets, so every app instance derives the same id for the same key.
    static func networkID(forKey key: String) -> UUID {
        func fnv1a(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in key.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
            return hash
        }
        let high = fnv1a(0xCBF2_9CE4_8422_2325)
        let low = fnv1a(0x6C62_272E_07BB_0142)
        var digest = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            digest[index] = UInt8(truncatingIfNeeded: high >> (8 * UInt64(index)))
            digest[index + 8] = UInt8(truncatingIfNeeded: low >> (8 * UInt64(index)))
        }
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
