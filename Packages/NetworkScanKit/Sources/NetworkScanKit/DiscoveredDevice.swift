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
        networkProfileID: UUID? = nil
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
    }

    public var displayName: String {
        hostname ?? ipAddress
    }

    public var latencyText: String {
        guard let latency else {
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
