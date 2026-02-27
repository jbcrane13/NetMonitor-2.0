import Foundation
import SwiftData

/// A locally-discovered network device, persisted via SwiftData.
/// This is the iOS-derived model (richer than the macOS equivalent).
@Model
public final class LocalDevice {
    @Attribute(.unique) public var id: UUID
    public var ipAddress: String
    public var macAddress: String
    public var hostname: String?
    public var vendor: String?
    public var deviceType: DeviceType
    public var customName: String?
    public var status: DeviceStatus
    public var lastLatency: Double?
    public var isGateway: Bool = false
    public var supportsWakeOnLan: Bool = false
    public var firstSeen: Date
    public var lastSeen: Date
    public var notes: String?
    public var resolvedHostname: String?
    public var manufacturer: String?
    public var openPorts: [Int]?
    public var discoveredServices: [String]?
    public var networkProfileID: UUID?

    public init(
        id: UUID = UUID(),
        ipAddress: String,
        macAddress: String,
        hostname: String? = nil,
        vendor: String? = nil,
        deviceType: DeviceType = .unknown,
        customName: String? = nil,
        status: DeviceStatus = .online,
        lastLatency: Double? = nil,
        isGateway: Bool = false,
        supportsWakeOnLan: Bool = false,
        notes: String? = nil,
        resolvedHostname: String? = nil,
        manufacturer: String? = nil,
        openPorts: [Int]? = nil,
        discoveredServices: [String]? = nil,
        networkProfileID: UUID? = nil
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.vendor = vendor
        self.deviceType = deviceType
        self.customName = customName
        self.status = status
        self.lastLatency = lastLatency
        self.isGateway = isGateway
        self.supportsWakeOnLan = supportsWakeOnLan
        self.firstSeen = Date()
        self.lastSeen = Date()
        self.notes = notes
        self.resolvedHostname = resolvedHostname
        self.manufacturer = manufacturer
        self.openPorts = openPorts
        self.discoveredServices = discoveredServices
        self.networkProfileID = networkProfileID
    }

    public var displayName: String {
        customName ?? resolvedHostname ?? hostname ?? ipAddress
    }

    public var formattedMacAddress: String {
        macAddress.uppercased()
    }

    public var latencyText: String? {
        guard let latency = lastLatency else { return nil }
        if latency < 1 { return "<1 ms" }
        return String(format: "%.0f ms", latency)
    }

    public func updateStatus(to newStatus: DeviceStatus) {
        status = newStatus
        lastSeen = Date()
    }

    public func updateLatency(_ latency: Double) {
        lastLatency = latency
        lastSeen = Date()
        if status == .offline {
            status = .online
        }
    }
}
