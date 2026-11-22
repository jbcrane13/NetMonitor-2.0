import Foundation

/// The method by which a device was discovered on the network.
public enum DeviceSource: String, Codable, Sendable {
    case local
    case macCompanion
    case bonjour
    case ssdp
}

/// A device found during a network scan.
public struct DiscoveredDevice: Identifiable, Codable, Sendable {
    public let id: UUID
    public let ipAddress: String
    public let hostname: String?
    public let vendor: String?
    public let macAddress: String?
    public let latency: Double?
    public let discoveredAt: Date
    public let source: DeviceSource
    public let networkProfileID: UUID?
    /// Ports found open by a quick TCP port scan. Additive/optional so older
    /// JSON caches (`UserDefaults`) that predate this field decode as `nil`.
    public let openPorts: [Int]?
    /// `true` when the device is only known from the ARP cache and gave no answer
    /// during the scan that produced it, so it may have left the network (#378).
    /// Older JSON caches without this field decode as `false`.
    public let isCached: Bool
    /// Maker, model and friendly name with their sources (ADR-022). Additive: older JSON
    /// caches decode with nil values or nil sources.
    public let identity: DeviceIdentity

    public var friendlyName: String? { identity.friendlyName?.value }
    /// The maker the device announced, or a guess from its names. See ``maker``.
    public var manufacturer: String? { identity.maker?.value }
    public var modelName: String? { identity.model?.value }
    /// The maker to show: the announced maker or the MAC-prefix maker (`vendor`), whichever
    /// ranks higher (ADR-022).
    public var maker: String? { identity.resolvedMaker(macPrefixMaker: vendor) }

    /// Convenience init for local TCP probe (backward compatible).
    public init(ipAddress: String, latency: Double, discoveredAt: Date, networkProfileID: UUID? = nil) {
        self.id = UUID()
        self.ipAddress = ipAddress
        self.hostname = nil
        self.vendor = nil
        self.macAddress = nil
        self.latency = latency
        self.discoveredAt = discoveredAt
        self.source = .local
        self.networkProfileID = networkProfileID
        self.openPorts = nil
        self.isCached = false
        self.identity = DeviceIdentity()
    }

    /// Full init with all fields. `vendor` is the MAC-prefix maker only; a maker from any
    /// other source goes in `identity`.
    public init(
        id: UUID = UUID(),
        ipAddress: String,
        hostname: String?,
        vendor: String?,
        macAddress: String?,
        latency: Double?,
        discoveredAt: Date,
        source: DeviceSource,
        networkProfileID: UUID? = nil,
        openPorts: [Int]? = nil,
        isCached: Bool = false,
        identity: DeviceIdentity = DeviceIdentity()
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.hostname = hostname
        self.vendor = vendor
        self.macAddress = macAddress
        self.latency = latency
        self.discoveredAt = discoveredAt
        self.source = source
        self.networkProfileID = networkProfileID
        self.openPorts = openPorts
        self.isCached = isCached
        self.identity = identity
    }

    private enum CodingKeys: String, CodingKey {
        case id, ipAddress, hostname, vendor, macAddress, latency, discoveredAt, source, networkProfileID, openPorts, isCached
        case friendlyName, manufacturer, modelName
        case friendlyNameSource, makerSource, modelSource
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        vendor = try container.decodeIfPresent(String.self, forKey: .vendor)
        macAddress = try container.decodeIfPresent(String.self, forKey: .macAddress)
        latency = try container.decodeIfPresent(Double.self, forKey: .latency)
        discoveredAt = try container.decode(Date.self, forKey: .discoveredAt)
        source = try container.decode(DeviceSource.self, forKey: .source)
        networkProfileID = try container.decodeIfPresent(UUID.self, forKey: .networkProfileID)
        openPorts = try container.decodeIfPresent([Int].self, forKey: .openPorts)
        isCached = try container.decodeIfPresent(Bool.self, forKey: .isCached) ?? false
        func value(_ key: CodingKeys, _ sourceKey: CodingKeys) throws -> IdentityValue? {
            try IdentityValue(
                container.decodeIfPresent(String.self, forKey: key),
                source: container.decodeIfPresent(IdentitySource.self, forKey: sourceKey)
            )
        }
        identity = try DeviceIdentity(
            maker: value(.manufacturer, .makerSource),
            model: value(.modelName, .modelSource),
            friendlyName: value(.friendlyName, .friendlyNameSource)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ipAddress, forKey: .ipAddress)
        try container.encodeIfPresent(hostname, forKey: .hostname)
        try container.encodeIfPresent(vendor, forKey: .vendor)
        try container.encodeIfPresent(macAddress, forKey: .macAddress)
        try container.encodeIfPresent(latency, forKey: .latency)
        try container.encode(discoveredAt, forKey: .discoveredAt)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(networkProfileID, forKey: .networkProfileID)
        try container.encodeIfPresent(openPorts, forKey: .openPorts)
        try container.encode(isCached, forKey: .isCached)
        try container.encodeIfPresent(identity.friendlyName?.value, forKey: .friendlyName)
        try container.encodeIfPresent(identity.friendlyName?.source, forKey: .friendlyNameSource)
        try container.encodeIfPresent(identity.maker?.value, forKey: .manufacturer)
        try container.encodeIfPresent(identity.maker?.source, forKey: .makerSource)
        try container.encodeIfPresent(identity.model?.value, forKey: .modelName)
        try container.encodeIfPresent(identity.model?.source, forKey: .modelSource)
    }

    /// A copy with `isCached` replaced; every other field is kept.
    public func withCached(_ isCached: Bool) -> DiscoveredDevice {
        DiscoveredDevice(
            id: id,
            ipAddress: ipAddress,
            hostname: hostname,
            vendor: vendor,
            macAddress: macAddress,
            latency: latency,
            discoveredAt: discoveredAt,
            source: source,
            networkProfileID: networkProfileID,
            openPorts: openPorts,
            isCached: isCached,
            identity: identity
        )
    }

    /// A copy with `identity` replaced; every other field is kept.
    public func withIdentity(_ identity: DeviceIdentity) -> DiscoveredDevice {
        DiscoveredDevice(
            id: id,
            ipAddress: ipAddress,
            hostname: hostname,
            vendor: vendor,
            macAddress: macAddress,
            latency: latency,
            discoveredAt: discoveredAt,
            source: source,
            networkProfileID: networkProfileID,
            openPorts: openPorts,
            isCached: isCached,
            identity: identity
        )
    }

    /// The device name: the friendly name, else the hostname, else the IP.
    public var displayName: String {
        friendlyName ?? hostname ?? ipAddress
    }

    public var latencyText: String {
        guard let latency else {
            if isCached {
                return "Cached"
            }
            switch source {
            case .macCompanion: return "via Mac"
            case .ssdp: return "UPnP"
            case .bonjour: return "Bonjour"
            default: return "—"
            }
        }
        if latency < 1 {
            return "<1 ms"
        }
        return String(format: "%.0f ms", latency)
    }
}

extension String {
    /// Sort key for dotted-decimal IPv4 addresses (numeric ordering).
    public var ipSortKey: Int {
        let parts = self.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return 0 }
        return parts[0] * 16_777_216 + parts[1] * 65_536 + parts[2] * 256 + parts[3]
    }
}

/// Lightweight mirror of a Bonjour service for use by ``BonjourScanPhase``.
///
/// The full `BonjourService` model lives in the main app; this struct carries
/// only the fields needed to resolve a service endpoint to an IP address.
public struct BonjourServiceInfo: Sendable {
    public let name: String
    public let type: String
    public let domain: String
    /// TXT record keys (lowercased) and values from the browse result, when known (#386).
    public let txtRecord: [String: String]

    public init(name: String, type: String, domain: String, txtRecord: [String: String] = [:]) {
        self.name = name
        self.type = type
        self.domain = domain
        self.txtRecord = txtRecord
    }
}
