import Foundation
import SwiftData

/// A macOS companion device paired with this iOS app.
/// Persisted via SwiftData.
@Model
public final class PairedMac {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var hostname: String?
    public var ipAddress: String?
    public var port: Int
    public var lastConnected: Date?
    public var isPrimary: Bool
    public var isConnected: Bool
    public var pairingCode: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        hostname: String? = nil,
        ipAddress: String? = nil,
        port: Int = 8849,
        lastConnected: Date? = nil,
        isPrimary: Bool = false,
        isConnected: Bool = false,
        pairingCode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.ipAddress = ipAddress
        self.port = port
        self.lastConnected = lastConnected
        self.isPrimary = isPrimary
        self.isConnected = isConnected
        self.pairingCode = pairingCode
        self.createdAt = Date()
    }

    public var displayAddress: String {
        if let ip = ipAddress { return "\(ip):\(port)" }
        if let host = hostname { return "\(host):\(port)" }
        return "Not configured"
    }

    public var connectionStatusText: String {
        if isConnected { return "Connected" }
        if lastConnected != nil { return "Disconnected" }
        return "Never connected"
    }
}
