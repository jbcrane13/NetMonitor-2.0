import Foundation

// MARK: - NetworkEventType

/// Types of network events that can be logged.
public enum NetworkEventType: String, Codable, CaseIterable, Sendable {
    case deviceJoined       = "deviceJoined"
    case deviceLeft         = "deviceLeft"
    case connectivityChange = "connectivityChange"
    case speedChange        = "speedChange"
    case scanComplete       = "scanComplete"
    case toolRun            = "toolRun"
    case vpnConnected       = "vpnConnected"
    case vpnDisconnected    = "vpnDisconnected"
    case gatewayChange      = "gatewayChange"

    public var displayName: String {
        switch self {
        case .deviceJoined:       return "Device Joined"
        case .deviceLeft:         return "Device Left"
        case .connectivityChange: return "Connectivity Change"
        case .speedChange:        return "Speed Change"
        case .scanComplete:       return "Scan Complete"
        case .toolRun:            return "Tool Run"
        case .vpnConnected:       return "VPN Connected"
        case .vpnDisconnected:    return "VPN Disconnected"
        case .gatewayChange:      return "Gateway Change"
        }
    }

    public var iconName: String {
        switch self {
        case .deviceJoined:       return "plus.circle.fill"
        case .deviceLeft:         return "minus.circle.fill"
        case .connectivityChange: return "wifi.exclamationmark"
        case .speedChange:        return "speedometer"
        case .scanComplete:       return "checkmark.circle.fill"
        case .toolRun:            return "wrench.and.screwdriver.fill"
        case .vpnConnected:       return "network.badge.shield.half.filled"
        case .vpnDisconnected:    return "network.slash"
        case .gatewayChange:      return "server.rack"
        }
    }
}

// MARK: - NetworkEventSeverity

/// Severity level for a network event.
public enum NetworkEventSeverity: String, Codable, Sendable {
    case info    = "info"
    case warning = "warning"
    case error   = "error"
    case success = "success"
}

// MARK: - NetworkEvent

/// A single recorded network event.
public struct NetworkEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let type: NetworkEventType
    public let timestamp: Date
    public let title: String
    public let details: String?
    public let severity: NetworkEventSeverity
    /// The `LocalDevice.id` the event is about, when it maps to one (#491). Nil in events
    /// written before #491 and for events that aren't about a device.
    public let deviceID: UUID?
    /// The `NetworkProfile.id` of the network the event happened on (#491). Nil in events
    /// written before #491.
    public let networkProfileID: UUID?

    public init(
        id: UUID = UUID(),
        type: NetworkEventType,
        timestamp: Date = Date(),
        title: String,
        details: String? = nil,
        severity: NetworkEventSeverity = .info,
        deviceID: UUID? = nil,
        networkProfileID: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.title = title
        self.details = details
        self.severity = severity
        self.deviceID = deviceID
        self.networkProfileID = networkProfileID
    }
}
