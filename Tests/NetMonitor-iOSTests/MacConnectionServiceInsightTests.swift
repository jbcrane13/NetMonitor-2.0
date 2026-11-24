import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_iOS

/// How the companion link feeds the Mac's model to the phone (#457).
@Suite(.serialized)
@MainActor
struct MacConnectionServiceInsightTests {
    private static func frame(json: String) -> Data {
        let body = Data(json.utf8)
        var length = UInt32(body.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(body)
        return data
    }

    @Test("a frame with an unknown type is skipped and the heartbeat after it still counts")
    func unknownTypeKeepsLink() async throws {
        let service = MacConnectionService.shared
        service.disconnect()
        defer { service.disconnect() }

        var stream = Self.frame(json: #"{"protocolVersion":1,"type":"futureThing","payload":{}}"#)
        try stream.append(CompanionMessage.heartbeat(HeartbeatPayload(capabilities: [CompanionCapability.insight])).encodeLengthPrefixed())
        await service.processIncomingDataForTesting(stream)

        #expect(service.linkSessionForTesting.lastReceived != nil)
        #expect(service.connectionState == .disconnected)
        #expect(PhoneInsight.mac.isAvailable)
    }

    @Test("the Mac counts for insight only while its heartbeats advertise insight.v1")
    func heartbeatCapabilityGatesMac() async throws {
        let service = MacConnectionService.shared
        service.disconnect()
        defer { service.disconnect() }

        try await service.processIncomingDataForTesting(CompanionMessage.heartbeat(HeartbeatPayload()).encodeLengthPrefixed())
        #expect(!PhoneInsight.mac.isAvailable)

        try await service.processIncomingDataForTesting(
            CompanionMessage.heartbeat(HeartbeatPayload(capabilities: [CompanionCapability.insight])).encodeLengthPrefixed()
        )
        #expect(PhoneInsight.mac.isAvailable)
    }

    @Test("disconnecting withdraws the Mac, so explanations fall back to the path without the model")
    func disconnectWithdrawsMac() async throws {
        let service = MacConnectionService.shared
        service.disconnect()
        try await service.processIncomingDataForTesting(
            CompanionMessage.heartbeat(HeartbeatPayload(capabilities: [CompanionCapability.insight])).encodeLengthPrefixed()
        )
        #expect(PhoneInsight.mac.isAvailable)

        service.disconnect()

        #expect(!PhoneInsight.mac.isAvailable)
        var updates: [InsightUpdate] = []
        for await update in PhoneInsight.mac.explain(InsightRequest(subject: "s", facts: ["f"])) {
            updates.append(update)
        }
        #expect(updates == [.unreachable])
    }

    @Test("with a Mac advertising insight but no link to send on, a request fails rather than waiting")
    func noLinkFailsAtOnce() async throws {
        let service = MacConnectionService.shared
        service.disconnect()
        defer { service.disconnect() }
        try await service.processIncomingDataForTesting(
            CompanionMessage.heartbeat(HeartbeatPayload(capabilities: [CompanionCapability.insight])).encodeLengthPrefixed()
        )

        var updates: [InsightUpdate] = []
        for await update in PhoneInsight.mac.explain(InsightRequest(subject: "s", facts: ["f"])) {
            updates.append(update)
        }
        #expect(updates == [.unreachable])
    }
}
