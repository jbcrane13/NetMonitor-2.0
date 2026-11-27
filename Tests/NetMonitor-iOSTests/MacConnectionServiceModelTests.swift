import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_iOS

/// How the companion link feeds the Mac's typed-text model to the phone (#586).
@Suite(.serialized)
@MainActor
struct MacConnectionServiceModelTests {
    private static func heartbeat(_ capabilities: [String]?) throws -> Data {
        try CompanionMessage.heartbeat(HeartbeatPayload(capabilities: capabilities)).encodeLengthPrefixed()
    }

    @Test("the phone sends a schema only while the Mac's latest heartbeat lists it")
    func latestHeartbeatGates() async throws {
        let service = MacConnectionService.shared
        service.disconnect()
        defer { service.disconnect() }

        try await service.processIncomingDataForTesting(Self.heartbeat(["rules.v1", "symptoms.v1"]))
        #expect(PhoneModel.linkClient.offers(.rules))
        #expect(PhoneModel.linkClient.offers(.symptoms))

        // The Mac's owner turned "Answer model requests from iPhone" off.
        try await service.processIncomingDataForTesting(Self.heartbeat(["inventory.v1"]))
        #expect(!PhoneModel.linkClient.offers(.rules))
        #expect(await PhoneModel.linkClient.request(.rules(text: "tell me if the NAS goes offline")) == .unavailable)
    }

    @Test("disconnecting withdraws the Mac, and the rule field falls back to hidden")
    func disconnectWithdraws() async throws {
        let service = MacConnectionService.shared
        service.disconnect()
        try await service.processIncomingDataForTesting(Self.heartbeat(["rules.v1"]))
        #expect(PhoneModel.linkClient.offers(.rules))
        service.disconnect()
        #expect(!PhoneModel.linkClient.offers(.rules))
        let parser = RoutedRuleIntentParser(
            local: UnavailableRuleIntentParser(), mac: PhoneModel.linkClient, consent: MacInsightConsent(defaults: nil, decision: true)
        )
        #expect(!parser.isAvailable)
    }

    @Test("with a Mac offering a schema but no link to send on, a request fails at once")
    func noLinkFailsAtOnce() async throws {
        let service = MacConnectionService.shared
        service.disconnect()
        defer { service.disconnect() }
        try await service.processIncomingDataForTesting(Self.heartbeat(["symptoms.v1"]))
        let started = ContinuousClock.now
        #expect(await PhoneModel.linkClient.request(.symptoms(text: "the wifi is weak")) == .unavailable)
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test("a send for a link that isn't current is refused")
    func staleLinkRefused() async {
        let message = CompanionMessage.modelCancel(ModelCancelPayload(requestID: UUID()))
        #expect(await MacConnectionService.shared.sendModel(message, on: UUID()) == false)
    }
}
