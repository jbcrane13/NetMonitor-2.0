import Foundation
import Testing
@testable import NetMonitorCore

@Suite("CompanionLinkAuthorizer")
struct CompanionLinkAuthorizerTests {
    /// One message of every type the protocol has.
    static let everyMessage: [CompanionMessage] = [
        .statusUpdate(StatusUpdatePayload(isMonitoring: true, onlineTargets: 1, offlineTargets: 0, averageLatency: nil)),
        .targetList(TargetListPayload(targets: [])),
        .deviceList(DeviceListPayload(devices: [])),
        .networkProfile(NetworkProfilePayload(name: "n", gatewayIP: "10.0.0.1", subnet: "10.0.0.0/24", interfaceName: "en0")),
        .command(CommandPayload(action: .scanDevices)),
        .toolResult(ToolResultPayload(tool: "ping", success: true, result: "")),
        .error(ErrorPayload(code: "E", message: "m")),
        .heartbeat(HeartbeatPayload()),
        .insightRequest(InsightRequestPayload(requestID: UUID(), request: InsightRequest(subject: "s", facts: ["a"]))),
        .insightResponse(InsightResponsePayload(requestID: UUID(), answer: "t")),
        .serverHello(ServerHelloPayload(macID: UUID(), macName: "Mac", mode: .paired)),
        .pairRequest(PairRequestPayload(kind: .qr, proof: Data(count: 32), nonce: Data(count: 32), phoneName: "iPhone")),
        .pairChallenge(PairChallengePayload(proof: Data(count: 32), nonce: Data(count: 32))),
        .pairResult(PairResultPayload(accepted: true)),
        .unpair(UnpairPayload()),
        .unknown(type: "futureThing")
    ]

    @Test("The sample covers every message type")
    func coversEveryType() {
        #expect(Set(Self.everyMessage.map(\.logName)).count == Self.everyMessage.count)
    }

    @Test("A link without a role refuses every message type", arguments: everyMessage)
    func unauthenticatedRefusesAll(message: CompanionMessage) {
        #expect(CompanionLinkAuthorizer.decide(message, role: nil) == .refuse)
    }

    @Test("A pairing link accepts only pairRequest and the phone's verdict", arguments: everyMessage)
    func pairingAcceptsOnlyPairingFrames(message: CompanionMessage) {
        let decision = CompanionLinkAuthorizer.decide(message, role: .pairing(window: UUID()))
        switch message {
        case .pairRequest: #expect(decision == .pairRequest)
        case .pairResult: #expect(decision == .pairVerdict)
        default: #expect(decision == .refuse)
        }
    }

    @Test("A paired link dispatches the phone's messages, handles unpair, and refuses pairing frames")
    func pairedLink() {
        let role = CompanionLinkRole.paired(pin: Data(count: 32), generation: 1)
        for message in Self.everyMessage {
            let decision = CompanionLinkAuthorizer.decide(message, role: role)
            switch message {
            case .serverHello, .pairRequest, .pairChallenge, .pairResult:
                #expect(decision == .refuse, "\(message.logName)")
            case .unpair:
                #expect(decision == .unpair)
            case .unknown:
                #expect(decision == .ignore)
            default:
                #expect(decision == .dispatch, "\(message.logName)")
            }
        }
    }
}

@Suite("Companion protocol v2")
struct CompanionProtocolV2Tests {
    @Test("A protocol v1 frame no longer decodes")
    func refusesV1() {
        let v1 = Data(#"{"protocolVersion":1,"type":"heartbeat","payload":{"timestamp":786000000,"version":"1.0"}}"#.utf8)
        #expect(throws: CompanionMessageDecodeError.versionMismatch(got: 1, expected: 2)) {
            try CompanionMessage.decode(from: v1)
        }
    }

    @Test("Every pairing frame round-trips", arguments: [
        CompanionMessage.serverHello(ServerHelloPayload(macID: UUID(), macName: "Mac", mode: .pairing, commitment: Data(repeating: 3, count: 32))),
        .pairRequest(PairRequestPayload(
            kind: .code, proof: Data(repeating: 7, count: 32), nonce: Data(repeating: 8, count: 32), phoneName: "iPhone"
        )),
        .pairChallenge(PairChallengePayload(proof: Data(repeating: 9, count: 32), nonce: Data(repeating: 6, count: 32))),
        .pairResult(PairResultPayload(accepted: false, reason: "Cancelled on the Mac")),
        .unpair(UnpairPayload())
    ])
    func roundTrips(message: CompanionMessage) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try encoder.encode(message)
        let decoded = try CompanionMessage.decode(from: json)
        #expect(try encoder.encode(decoded) == json)
        #expect(decoded.logName == message.logName)
    }

    @Test("A pairing frame with an unknown mode fails to decode instead of falling back")
    func strictPairingFrames() {
        let text = #"{"protocolVersion":2,"type":"serverHello","payload":"#
            + #"{"macID":"6F1C2B4A-8D3E-4F5A-9B7C-1D2E3F4A5B6C","macName":"M","mode":"admin"}}"#
        let json = Data(text.utf8)
        #expect(throws: (any Error).self) { try CompanionMessage.decode(from: json) }
    }
}
