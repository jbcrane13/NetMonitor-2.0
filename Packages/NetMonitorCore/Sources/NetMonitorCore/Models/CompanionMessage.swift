import Foundation

// MARK: - CompanionMessage
/// Root message type for macOS ↔ iOS companion communication.
/// Uses length-prefixed JSON framing: 4-byte big-endian length prefix + JSON payload.
/// JSON format: { "type": "<messageType>", "payload": { ... } }

public enum CompanionMessage: Codable, Sendable {
    case statusUpdate(StatusUpdatePayload)
    case targetList(TargetListPayload)
    case deviceList(DeviceListPayload)
    case command(CommandPayload)
    case toolResult(ToolResultPayload)
    case error(ErrorPayload)
    case heartbeat(HeartbeatPayload)

    // MARK: Coding Keys

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case statusUpdate
        case targetList
        case deviceList
        case command
        case toolResult
        case error
        case heartbeat
    }

    // MARK: Decodable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)

        switch type {
        case .statusUpdate:
            self = .statusUpdate(try container.decode(StatusUpdatePayload.self, forKey: .payload))
        case .targetList:
            self = .targetList(try container.decode(TargetListPayload.self, forKey: .payload))
        case .deviceList:
            self = .deviceList(try container.decode(DeviceListPayload.self, forKey: .payload))
        case .command:
            self = .command(try container.decode(CommandPayload.self, forKey: .payload))
        case .toolResult:
            self = .toolResult(try container.decode(ToolResultPayload.self, forKey: .payload))
        case .error:
            self = .error(try container.decode(ErrorPayload.self, forKey: .payload))
        case .heartbeat:
            self = .heartbeat(try container.decode(HeartbeatPayload.self, forKey: .payload))
        }
    }

    // MARK: Encodable

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .statusUpdate(let payload):
            try container.encode(MessageType.statusUpdate, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .targetList(let payload):
            try container.encode(MessageType.targetList, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .deviceList(let payload):
            try container.encode(MessageType.deviceList, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .command(let payload):
            try container.encode(MessageType.command, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .toolResult(let payload):
            try container.encode(MessageType.toolResult, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .error(let payload):
            try container.encode(MessageType.error, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .heartbeat(let payload):
            try container.encode(MessageType.heartbeat, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

// MARK: - Payload Types

public struct StatusUpdatePayload: Codable, Sendable {
    public let isMonitoring: Bool
    public let onlineTargets: Int
    public let offlineTargets: Int
    public let averageLatency: Double?
    public let timestamp: Date

    public init(
        isMonitoring: Bool,
        onlineTargets: Int,
        offlineTargets: Int,
        averageLatency: Double?,
        timestamp: Date = Date()
    ) {
        self.isMonitoring = isMonitoring
        self.onlineTargets = onlineTargets
        self.offlineTargets = offlineTargets
        self.averageLatency = averageLatency
        self.timestamp = timestamp
    }
}

public struct TargetListPayload: Codable, Sendable {
    public let targets: [TargetInfo]

    public init(targets: [TargetInfo]) {
        self.targets = targets
    }
}

public struct TargetInfo: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let host: String
    public let port: Int?
    public let `protocol`: String
    public let isEnabled: Bool
    public let isReachable: Bool?
    public let latency: Double?

    public init(
        id: UUID,
        name: String,
        host: String,
        port: Int?,
        protocol: String,
        isEnabled: Bool,
        isReachable: Bool?,
        latency: Double?
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.protocol = `protocol`
        self.isEnabled = isEnabled
        self.isReachable = isReachable
        self.latency = latency
    }
}

public struct DeviceListPayload: Codable, Sendable {
    public let devices: [DeviceInfo]

    public init(devices: [DeviceInfo]) {
        self.devices = devices
    }
}

public struct DeviceInfo: Codable, Sendable, Identifiable {
    public let id: UUID
    public let ipAddress: String
    public let macAddress: String
    public let hostname: String?
    public let vendor: String?
    public let deviceType: String
    public let isOnline: Bool

    public init(
        id: UUID = UUID(),
        ipAddress: String,
        macAddress: String,
        hostname: String?,
        vendor: String? = nil,
        deviceType: String = "unknown",
        isOnline: Bool
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.vendor = vendor
        self.deviceType = deviceType
        self.isOnline = isOnline
    }
}

public struct CommandPayload: Codable, Sendable {
    public let action: CommandAction
    public let parameters: [String: String]?

    public init(action: CommandAction, parameters: [String: String]? = nil) {
        self.action = action
        self.parameters = parameters
    }
}

public enum CommandAction: String, Codable, Sendable {
    case startMonitoring
    case stopMonitoring
    case scanDevices
    case ping
    case traceroute
    case portScan
    case dnsLookup
    case wakeOnLan
    case refreshTargets
    case refreshDevices
}

public struct ToolResultPayload: Codable, Sendable {
    public let tool: String
    public let success: Bool
    public let result: String
    public let timestamp: Date

    public init(tool: String, success: Bool, result: String, timestamp: Date = Date()) {
        self.tool = tool
        self.success = success
        self.result = result
        self.timestamp = timestamp
    }
}

public struct ErrorPayload: Codable, Sendable {
    public let code: String
    public let message: String
    public let timestamp: Date

    public init(code: String, message: String, timestamp: Date = Date()) {
        self.code = code
        self.message = message
        self.timestamp = timestamp
    }
}

public struct HeartbeatPayload: Codable, Sendable {
    public let timestamp: Date
    public let version: String

    public init(timestamp: Date = Date(), version: String = "1.0") {
        self.timestamp = timestamp
        self.version = version
    }
}

// MARK: - JSON Encoder/Decoder Configuration

extension CompanionMessage {
    /// Shared JSON encoder for the companion service wire format.
    public static let jsonEncoder: JSONEncoder = JSONEncoder()

    /// Shared JSON decoder for the companion service wire format.
    public static let jsonDecoder: JSONDecoder = JSONDecoder()

    /// Encode this message to length-prefixed JSON data.
    /// Format: 4-byte big-endian length prefix + JSON payload.
    public func encodeLengthPrefixed() throws -> Data {
        let jsonData = try Self.jsonEncoder.encode(self)
        var length = UInt32(jsonData.count).bigEndian
        var frameData = Data(bytes: &length, count: 4)
        frameData.append(jsonData)
        return frameData
    }

    /// Decode a CompanionMessage from raw JSON data (without length prefix).
    public static func decode(from data: Data) throws -> CompanionMessage {
        try jsonDecoder.decode(CompanionMessage.self, from: data)
    }
}
