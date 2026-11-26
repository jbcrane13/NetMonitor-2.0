import Foundation
import NetworkScanKit

// MARK: - CompanionMessage
/// Root message type for macOS ↔ iOS companion communication.
/// Uses length-prefixed JSON framing: 4-byte big-endian length prefix + JSON payload.
/// JSON format: { "protocolVersion": 2, "type": "<messageType>", "payload": { ... } }
/// Every frame travels inside the pinned TLS 1.3 link (#590, `CompanionTLS`).

public enum CompanionMessage: Codable, Sendable {
    /// 2 since #590: the link is TLS 1.3 with pinned identities and a pairing handshake. A
    /// deliberate break, not a capability: a v1 peer can't complete the handshake at all.
    public static let currentProtocolVersion = 2

    case statusUpdate(StatusUpdatePayload)
    case targetList(TargetListPayload)
    case deviceList(DeviceListPayload)
    case networkProfile(NetworkProfilePayload)
    case command(CommandPayload)
    case toolResult(ToolResultPayload)
    case error(ErrorPayload)
    case heartbeat(HeartbeatPayload)
    /// iPhone → Mac: word an insight with the Mac's model. Sent only to a Mac whose heartbeat
    /// offers `CompanionCapability.insight` (#457).
    case insightRequest(InsightRequestPayload)
    /// Mac → iPhone: the answer to one `insightRequest`, never sent unprompted (#457).
    case insightResponse(InsightResponsePayload)
    /// Mac → iPhone, first on every link once the Mac has verified the session: the phone sends
    /// nothing before it (#590).
    case serverHello(ServerHelloPayload)
    /// iPhone → Mac on a pairing link: proof of the one-time secret over this session (#590).
    case pairRequest(PairRequestPayload)
    /// Mac → iPhone on a pairing link: the Mac's proof of the same secret (#590).
    case pairChallenge(PairChallengePayload)
    /// Mac → iPhone: whether the user confirmed the pairing on the Mac (#590).
    case pairResult(PairResultPayload)
    /// iPhone → Mac on a paired link: this phone forgot the Mac; remove its pin (#590).
    case unpair(UnpairPayload)
    /// A type this build doesn't know, from a newer peer: kept so the frame decodes, and
    /// ignored by both sides (Models/AGENTS.md: Codable enums get an unknown fallback). New
    /// types are still sent only to a peer that advertised them.
    case unknown(type: String)

    // MARK: Coding Keys

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case statusUpdate
        case targetList
        case deviceList
        case networkProfile
        case command
        case toolResult
        case error
        case heartbeat
        case insightRequest
        case insightResponse
        case serverHello
        case pairRequest
        case pairChallenge
        case pairResult
        case unpair
    }

    // MARK: Decodable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? Self.currentProtocolVersion
        guard protocolVersion == Self.currentProtocolVersion else {
            throw CompanionMessageDecodeError.versionMismatch(
                got: protocolVersion,
                expected: Self.currentProtocolVersion
            )
        }
        let typeName = try container.decode(String.self, forKey: .type)
        guard let type = MessageType(rawValue: typeName) else {
            self = .unknown(type: typeName)
            return
        }

        switch type {
        case .statusUpdate:
            self = try .statusUpdate(container.decode(StatusUpdatePayload.self, forKey: .payload))
        case .targetList:
            self = try .targetList(container.decode(TargetListPayload.self, forKey: .payload))
        case .deviceList:
            self = try .deviceList(container.decode(DeviceListPayload.self, forKey: .payload))
        case .networkProfile:
            self = try .networkProfile(container.decode(NetworkProfilePayload.self, forKey: .payload))
        case .command:
            self = try .command(container.decode(CommandPayload.self, forKey: .payload))
        case .toolResult:
            self = try .toolResult(container.decode(ToolResultPayload.self, forKey: .payload))
        case .error:
            self = try .error(container.decode(ErrorPayload.self, forKey: .payload))
        case .heartbeat:
            self = try .heartbeat(container.decode(HeartbeatPayload.self, forKey: .payload))
        case .insightRequest:
            self = try .insightRequest(container.decode(InsightRequestPayload.self, forKey: .payload))
        case .insightResponse:
            self = try .insightResponse(container.decode(InsightResponsePayload.self, forKey: .payload))
        case .serverHello:
            self = try .serverHello(container.decode(ServerHelloPayload.self, forKey: .payload))
        case .pairRequest:
            self = try .pairRequest(container.decode(PairRequestPayload.self, forKey: .payload))
        case .pairChallenge:
            self = try .pairChallenge(container.decode(PairChallengePayload.self, forKey: .payload))
        case .pairResult:
            self = try .pairResult(container.decode(PairResultPayload.self, forKey: .payload))
        case .unpair:
            self = try .unpair(container.decode(UnpairPayload.self, forKey: .payload))
        }
    }

    // MARK: Encodable

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentProtocolVersion, forKey: .protocolVersion)

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
        case .networkProfile(let payload):
            try container.encode(MessageType.networkProfile, forKey: .type)
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
        case .insightRequest(let payload):
            try container.encode(MessageType.insightRequest, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .insightResponse(let payload):
            try container.encode(MessageType.insightResponse, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .serverHello(let payload):
            try container.encode(MessageType.serverHello, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .pairRequest(let payload):
            try container.encode(MessageType.pairRequest, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .pairChallenge(let payload):
            try container.encode(MessageType.pairChallenge, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .pairResult(let payload):
            try container.encode(MessageType.pairResult, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .unpair(let payload):
            try container.encode(MessageType.unpair, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .unknown(let type):
            try container.encode(type, forKey: .type)
            try container.encode([String: String](), forKey: .payload)
        }
    }
}

public enum CompanionMessageDecodeError: Error, Equatable, LocalizedError, Sendable {
    case versionMismatch(got: Int, expected: Int)

    public var errorDescription: String? {
        switch self {
        case .versionMismatch(let got, let expected):
            return "Companion protocol version mismatch: got \(got), expected \(expected)"
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
    /// The network the list covers and how old its latest scan was (#585). Nil from a Mac before
    /// `inventory.v1`.
    public let network: InventoryNetwork?
    /// True when the Mac trimmed the list to fit one frame (#624); nil otherwise and from older Macs.
    public let truncated: Bool?

    public init(devices: [DeviceInfo], network: InventoryNetwork? = nil, truncated: Bool? = nil) {
        self.devices = devices
        self.network = network
        self.truncated = truncated
    }
}

/// The network a Mac's device list covers (#585): the phone shows the list only on the same
/// subnet. `scanAge` is how long before sending the Mac's latest scan of it was, on the Mac's
/// clock alone, so the phone places the scan on its own clock (#619).
public struct InventoryNetwork: Codable, Sendable, Equatable {
    /// CIDR, as `NetworkProfile.subnetCIDR` writes it ("192.168.1.0/24"); nil when the Mac has no
    /// network, and then the phone shows nothing from the list.
    public let subnet: String?
    /// The Mac's routed gateway on that network (not the profile's first-host guess); nil when its
    /// route lookup failed.
    public let gatewayIP: String?
    public let name: String?
    public let scanAge: TimeInterval?

    public init(subnet: String?, gatewayIP: String?, name: String?, scanAge: TimeInterval?) {
        self.subnet = subnet
        self.gatewayIP = gatewayIP
        self.name = name
        self.scanAge = scanAge
    }
}

/// A device's maker, model and friendly name as the Mac ranked them (#427, ADR-022), each with
/// its source as a string: a source this build doesn't know reads as none instead of failing the
/// list. Model suggestions are never sent (#449).
public struct InventoryIdentity: Codable, Sendable, Equatable {
    public struct Value: Codable, Sendable, Equatable {
        public let value: String
        public let source: String?
    }

    public let maker: Value?
    public let model: Value?
    public let friendlyName: Value?

    public init(_ identity: DeviceIdentity) {
        let sent = identity.withoutSuggestions
        func value(_ item: IdentityValue?) -> Value? {
            item.map { Value(value: $0.value, source: $0.source?.rawValue) }
        }
        maker = value(sent.maker)
        model = value(sent.model)
        friendlyName = value(sent.friendlyName)
    }

    /// The identity with its sources; an unknown source is none.
    public var deviceIdentity: DeviceIdentity {
        func value(_ item: Value?) -> IdentityValue? {
            item.flatMap { IdentityValue($0.value, source: $0.source.flatMap(IdentitySource.init(rawValue:))) }
        }
        return DeviceIdentity(maker: value(maker), model: value(model), friendlyName: value(friendlyName))
    }
}

public struct NetworkProfilePayload: Codable, Sendable {
    public let name: String
    public let gatewayIP: String
    public let subnet: String
    public let interfaceName: String
    public let sourceDeviceName: String?

    public init(
        name: String,
        gatewayIP: String,
        subnet: String,
        interfaceName: String,
        sourceDeviceName: String? = nil
    ) {
        self.name = name
        self.gatewayIP = gatewayIP
        self.subnet = subnet
        self.interfaceName = interfaceName
        self.sourceDeviceName = sourceDeviceName
    }
}

/// One device on the Mac (#594: a device, not a row). `id` is the device's ID (its group's, or its
/// row's); `ipAddress`, `macAddress` and `isOnline` are the current interface's and whether the
/// device answered the Mac's latest scan, as an older phone reads them. A newer phone reads
/// `members` (absent from an older Mac) and `isDeviceOnline`.
public struct DeviceInfo: Codable, Sendable, Identifiable {
    public let id: UUID
    public let ipAddress: String
    public let macAddress: String
    public let hostname: String?
    public let vendor: String?
    public let deviceType: String
    public let isOnline: Bool
    /// Every interface, with its own sighting (#594 PR2). Nil from a Mac before it.
    public let members: [MemberInfo]?
    /// What the Mac shows for the device (any interface online, within grace), apart from
    /// `isOnline`'s "answered the latest scan".
    public let isDeviceOnline: Bool?
    /// How long before the list was sent any interface last answered, on the Mac's clock (#585).
    public let lastSeenAge: TimeInterval?
    /// How long before the list was sent the device last joined or left, from the Mac's event log;
    /// nil when it has none (#585).
    public let lastChangedAge: TimeInterval?
    /// The primary's maker, model and friendly name with their sources (#427).
    public let identity: InventoryIdentity?

    public init(
        id: UUID = UUID(),
        ipAddress: String,
        macAddress: String,
        hostname: String?,
        vendor: String? = nil,
        deviceType: String = "unknown",
        isOnline: Bool,
        members: [MemberInfo]? = nil,
        isDeviceOnline: Bool? = nil,
        lastSeenAge: TimeInterval? = nil,
        lastChangedAge: TimeInterval? = nil,
        identity: InventoryIdentity? = nil
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.vendor = vendor
        self.deviceType = deviceType
        self.isOnline = isOnline
        self.members = members
        self.isDeviceOnline = isDeviceOnline
        self.lastSeenAge = lastSeenAge
        self.lastChangedAge = lastChangedAge
        self.identity = identity
    }
}

/// One interface of a device on the Mac (#594 PR2): whether it answered the Mac's latest scan of
/// its network, and when that scan was, so the phone can tell a new sighting from an old one.
public struct MemberInfo: Codable, Sendable, Equatable, Identifiable {
    /// The interface's row ID on the Mac.
    public let id: UUID
    public let ipAddress: String
    public let macAddress: String?
    public let lastSeen: Date
    public let answeredLatestScan: Bool
    /// When the Mac's latest scan of the network was reconciled, on the Mac's clock; nil when it
    /// has none.
    public let scanTime: Date?
    /// How long before the list was sent that scan was, measured on the Mac's clock alone. The
    /// phone places the scan on its own clock as `receivedAt - scanAge`, so the two devices' wall
    /// clocks are never compared (#619).
    public let scanAge: TimeInterval?
    /// Whether this is the device's primary interface, the one its `hostname` names (#619). The
    /// phone gives the name to this member's sighting only. Nil from a Mac that doesn't say.
    public let isPrimary: Bool?

    public init(
        id: UUID, ipAddress: String, macAddress: String?, lastSeen: Date, answeredLatestScan: Bool, scanTime: Date?,
        scanAge: TimeInterval? = nil, isPrimary: Bool? = nil
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.lastSeen = lastSeen
        self.answeredLatestScan = answeredLatestScan
        self.scanTime = scanTime
        self.scanAge = scanAge
        self.isPrimary = isPrimary
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
    /// What the sender can do beyond the base protocol, such as `CompanionCapability.insight`.
    /// Optional, so older builds ignore it and their heartbeats, which lack it, still decode.
    public let capabilities: [String]?

    public init(timestamp: Date = Date(), version: String = "1.0", capabilities: [String]? = nil) {
        self.timestamp = timestamp
        self.version = version
        self.capabilities = capabilities
    }

    /// Whether the sender answers `insightRequest`s.
    public var offersInsight: Bool { capabilities?.contains(CompanionCapability.insight) == true }

    /// Whether the sender pushes its device inventory (#585).
    public var offersInventory: Bool { capabilities?.contains(CompanionCapability.inventory) == true }
}

/// Capabilities a peer advertises in `HeartbeatPayload.capabilities`. New message types are
/// sent only to a peer that advertised them, so the protocol version never has to change.
public enum CompanionCapability {
    /// The Mac answers `insightRequest` with its on-device model (#457).
    public static let insight = "insight.v1"
    /// The Mac sends its device inventory (`deviceList` with `network`, ages and identity) after
    /// each scan, and the phone shows it as the Mac's (#585).
    public static let inventory = "inventory.v1"
}

// MARK: - Logging

extension CompanionMessage {
    /// The message's type and nothing of its payload, for logs: payloads carry addresses,
    /// hostnames and, in insight requests, whole prompts.
    public var logName: String {
        switch self {
        case .statusUpdate: "statusUpdate"
        case .targetList: "targetList"
        case .deviceList: "deviceList"
        case .networkProfile: "networkProfile"
        case .command: "command"
        case .toolResult: "toolResult"
        case .error: "error"
        case .heartbeat: "heartbeat"
        case .insightRequest: "insightRequest"
        case .insightResponse: "insightResponse"
        case .serverHello: "serverHello"
        case .pairRequest: "pairRequest"
        case .pairChallenge: "pairChallenge"
        case .pairResult: "pairResult"
        case .unpair: "unpair"
        case .unknown: "unknown"
        }
    }
}

// MARK: - JSON Encoder/Decoder Configuration

extension CompanionMessage {
    // JSONEncoder/JSONDecoder are not thread-safe; compute vars create a new instance
    // per call to avoid data races when tests or services encode/decode concurrently.
    public static var jsonEncoder: JSONEncoder { JSONEncoder() }
    public static var jsonDecoder: JSONDecoder { JSONDecoder() }

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
