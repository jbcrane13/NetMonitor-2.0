import Foundation
import Testing
@testable import NetMonitorCore

/// The insight message pair and the capability that gates it (#457).
struct CompanionInsightMessageTests {
    private static let request = InsightRequest(
        subject: "Port scan of 192.168.1.20",
        facts: ["Open ports (1): 22 (SSH)"],
        observations: ["SSH is open"],
        kind: .explanation
    )

    private static func roundTrip(_ message: CompanionMessage) throws -> CompanionMessage {
        let framed = try message.encodeLengthPrefixed()
        return try CompanionMessage.decode(from: framed.dropFirst(4))
    }

    @Test("an insight request survives the wire with its request, devices and id")
    func insightRequestRoundTrip() throws {
        let id = try #require(UUID(uuidString: "6B1B5E36-2C0C-4E57-9C1D-3D4A0F5E7A11"))
        let deviceID = try #require(UUID(uuidString: "0F0E7C4D-5B7A-4A55-8C36-0E2A47C6E2B9"))
        let payload = InsightRequestPayload(
            requestID: id,
            request: Self.request,
            devices: [InsightDeviceReference(id: deviceID, displayName: "Garage Camera")]
        )

        guard case let .insightRequest(decoded) = try Self.roundTrip(.insightRequest(payload)) else {
            Issue.record("expected an insight request")
            return
        }
        #expect(decoded.requestID == id)
        #expect(decoded.request == Self.request)
        #expect(decoded.devices == [InsightDeviceReference(id: deviceID, displayName: "Garage Camera")])
    }

    @Test("every request kind keeps its kind on the wire", arguments: [
        InsightRequest.Kind.explanation, .summary, .notification, .advice
    ])
    func kindsRoundTrip(kind: InsightRequest.Kind) throws {
        let request = InsightRequest(subject: "s", facts: ["f"], kind: kind)
        guard case let .insightRequest(decoded) = try Self.roundTrip(.insightRequest(InsightRequestPayload(requestID: UUID(), request: request)))
        else {
            Issue.record("expected an insight request")
            return
        }
        #expect(decoded.request?.kind == kind)
    }

    @Test("a request kind this build doesn't know decodes, but carries no request")
    func unknownKindDecodesWithoutRequest() throws {
        let json = """
        {"protocolVersion":1,"type":"insightRequest","payload":{"requestID":"6B1B5E36-2C0C-4E57-9C1D-3D4A0F5E7A11",\
        "kind":"poem","subject":"s","facts":[],"observations":[]}}
        """
        guard case let .insightRequest(decoded) = try CompanionMessage.decode(from: Data(json.utf8)) else {
            Issue.record("expected an insight request")
            return
        }
        #expect(decoded.request == nil)
        #expect(decoded.devices == nil)
    }

    @Test("a message's log name is its type, with nothing of the prompt or the answer")
    func logNameLeavesOutThePayload() {
        let request = InsightRequest(subject: "Port scan of 192.168.1.20", facts: ["Host: nas.local"], observations: ["SSH is open"])
        let asked = CompanionMessage.insightRequest(InsightRequestPayload(requestID: UUID(), request: request, devices: nil))
        let answered = CompanionMessage.insightResponse(InsightResponsePayload(requestID: UUID(), answer: "nas.local has SSH open."))

        #expect(asked.logName == "insightRequest")
        #expect(answered.logName == "insightResponse")
    }

    @Test("an answer and each failure reason survive the wire")
    func insightResponseRoundTrip() throws {
        let id = UUID()
        let answer = InsightResponsePayload(requestID: id, answer: "SSH is open.")
        guard case let .insightResponse(answered) = try Self.roundTrip(.insightResponse(answer)) else {
            Issue.record("expected an insight response")
            return
        }
        #expect(answered.requestID == id)
        #expect(answered.answer == "SSH is open.")
        #expect(answered.failureReason == nil)

        for reason in InsightFailureReason.allCases {
            guard case let .insightResponse(failed) = try Self.roundTrip(.insightResponse(InsightResponsePayload(requestID: id, failure: reason)))
            else {
                Issue.record("expected an insight response")
                return
            }
            #expect(failed.answer == nil)
            #expect(failed.failureReason == reason)
        }
    }

    @Test("a failure reason this build doesn't know still reads as a failure")
    func unknownFailureReason() throws {
        let json = """
        {"protocolVersion":1,"type":"insightResponse","payload":{"requestID":"6B1B5E36-2C0C-4E57-9C1D-3D4A0F5E7A11","failure":"overheated"}}
        """
        guard case let .insightResponse(decoded) = try CompanionMessage.decode(from: Data(json.utf8)) else {
            Issue.record("expected an insight response")
            return
        }
        #expect(decoded.answer == nil)
        #expect(decoded.failureReason == .refused)
    }

    @Test("a heartbeat from an older build, without capabilities, still decodes")
    func oldHeartbeatDecodes() throws {
        let json = """
        {"protocolVersion":1,"type":"heartbeat","payload":{"timestamp":786000000,"version":"1.0"}}
        """
        guard case let .heartbeat(payload) = try CompanionMessage.decode(from: Data(json.utf8)) else {
            Issue.record("expected a heartbeat")
            return
        }
        #expect(payload.version == "1.0")
        #expect(payload.capabilities == nil)
        #expect(!payload.offersInsight)
    }

    @Test("a heartbeat carries the insight capability, and omits the field when there is none")
    func heartbeatCapabilities() throws {
        guard case let .heartbeat(payload) = try Self.roundTrip(.heartbeat(HeartbeatPayload(capabilities: [CompanionCapability.insight])))
        else {
            Issue.record("expected a heartbeat")
            return
        }
        #expect(payload.capabilities == ["insight.v1"])
        #expect(payload.offersInsight)

        let plain = try CompanionMessage.jsonEncoder.encode(CompanionMessage.heartbeat(HeartbeatPayload()))
        #expect(String(bytes: plain, encoding: .utf8)?.contains("capabilities") == false)
    }

    @Test("a frame with a type this build doesn't know is dropped, and the next frame still arrives")
    func unknownTypeFrameKeepsStream() async throws {
        let unknown = Data(#"{"protocolVersion":1,"type":"futureThing","payload":{}}"#.utf8)
        var length = UInt32(unknown.count).bigEndian
        var stream = Data(bytes: &length, count: 4)
        stream.append(unknown)
        try stream.append(CompanionMessage.heartbeat(HeartbeatPayload()).encodeLengthPrefixed())

        let batch = await CompanionFrameDecoder().append(stream)

        #expect(batch.errors == [.malformedPayload])
        #expect(batch.messages.count == 1)
        guard case .heartbeat = batch.messages.first else {
            Issue.record("expected the heartbeat after the unknown frame")
            return
        }
    }
}
