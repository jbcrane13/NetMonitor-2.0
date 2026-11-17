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
    /// From the device's UPnP description (#387). Additive: older JSON caches decode as nil.
    public let friendlyName: String?
    public let manufacturer: String?
    public let modelName: String?

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
        self.friendlyName = nil
        self.manufacturer = nil
        self.modelName = nil
    }

    /// Full init with all fields.
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
        friendlyName: String? = nil,
        manufacturer: String? = nil,
        modelName: String? = nil
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
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.modelName = modelName
    }

    private enum CodingKeys: String, CodingKey {
        case id, ipAddress, hostname, vendor, macAddress, latency, discoveredAt, source, networkProfileID, openPorts, isCached
        case friendlyName, manufacturer, modelName
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
        friendlyName = try container.decodeIfPresent(String.self, forKey: .friendlyName)
        manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
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
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            modelName: modelName
        )
    }

    /// The hostname, else the UPnP friendly name (#387), else the IP.
    public var displayName: String {
        hostname ?? friendlyName ?? ipAddress
    }

    /// The vendor (OUI or companion), else the UPnP manufacturer (#387).
    public var vendorOrManufacturer: String? {
        if let vendor, !vendor.isEmpty {
            return vendor
        }
        return manufacturer
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

    public init(name: String, type: String, domain: String) {
        self.name = name
        self.type = type
        self.domain = domain
    }
}
