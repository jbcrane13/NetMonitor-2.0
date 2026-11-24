import Foundation
import Testing
@testable import NetMonitorCore

/// The phone asks once before routing requests to the Mac (#457, Blake's opt-in decision).
@Suite(.serialized)
struct MacInsightConsentTests {
    private static let request = InsightRequest(subject: "s", facts: ["f"], observations: ["k"])

    /// A consent store in its own defaults suite, so no test sees another's answer.
    private static func makeConsent() -> MacInsightConsent {
        let suite = "MacInsightConsentTests.\(UUID().uuidString)"
        return MacInsightConsent(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    private static func capableMac(_ link: FakeLink) -> CompanionInsightClient {
        let client = CompanionInsightClient(send: link.send)
        client.received(heartbeat: HeartbeatPayload(capabilities: [CompanionCapability.insight]))
        return client
    }

    private static func updates(_ stream: AsyncStream<InsightUpdate>) async -> [InsightUpdate] {
        var all: [InsightUpdate] = []
        for await update in stream { all.append(update) }
        return all
    }

    @Test("before the user agrees, the Mac route is unavailable and nothing is sent")
    func notAgreedSendsNothing() async {
        let link = FakeLink()
        let consent = Self.makeConsent()
        let routed = RoutedInsightService(local: UnavailableInsightService(), mac: Self.capableMac(link), consent: consent)

        #expect(consent.decision == nil)
        #expect(!routed.isAvailable)
        #expect(routed.answerSource == nil)
        #expect(await Self.updates(routed.explain(Self.request)) == [.unreachable])
        #expect(link.sent.isEmpty)
    }

    @Test("the phone asks only while a capable Mac could answer what the local model can't, and only once")
    func asksOnce() {
        let consent = Self.makeConsent()
        let mac = Self.capableMac(FakeLink())

        #expect(RoutedInsightService(local: UnavailableInsightService(), mac: mac, consent: consent).availability == .needsConsent)
        #expect(!RoutedInsightService(local: FixedAnswerInsightService(answer: "x"), mac: mac, consent: consent).shouldAskForMac)
        #expect(!RoutedInsightService(local: UnavailableInsightService(), mac: CompanionInsightClient(send: FakeLink().send), consent: consent)
            .shouldAskForMac)

        consent.decline()
        #expect(RoutedInsightService(local: UnavailableInsightService(), mac: mac, consent: consent).availability == .unavailable)
    }

    @Test("agreeing enables the Mac route, and requests go to the Mac")
    func agreeingEnables() async throws {
        let link = FakeLink()
        let consent = Self.makeConsent()
        let mac = Self.capableMac(link)
        let routed = RoutedInsightService(local: UnavailableInsightService(), mac: mac, consent: consent)

        consent.agree()

        #expect(routed.isAvailable)
        #expect(routed.answerSource == .mac)
        #expect(!routed.shouldAskForMac)
        let collected = Task { await Self.updates(routed.explain(Self.request)) }
        await waitUntil { link.sent.count == 1 }
        let sent = try #require(link.sentRequests.first)
        mac.received(InsightResponsePayload(requestID: sent.requestID, answer: "Done."))
        #expect(await collected.value == [.finished("Done.")])
    }

    @Test("the Settings switch turns the Mac route off again, and declining leaves it off")
    func switchTurnsItOff() async {
        let link = FakeLink()
        let consent = Self.makeConsent()
        let routed = RoutedInsightService(local: UnavailableInsightService(), mac: Self.capableMac(link), consent: consent)
        consent.agree()
        #expect(routed.isAvailable)

        consent.setAllowed(false)

        #expect(consent.decision == false)
        #expect(!routed.isAvailable)
        #expect(await Self.updates(routed.explain(Self.request)) == [.unreachable])
        #expect(link.sent.isEmpty)

        consent.setAllowed(true)
        #expect(routed.isAvailable)
    }

    @Test("the answer is remembered across launches")
    func answerPersists() throws {
        let suite = "MacInsightConsentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        MacInsightConsent(defaults: defaults).decline()
        #expect(MacInsightConsent(defaults: defaults).decision == false)
        MacInsightConsent(defaults: defaults).agree()
        #expect(MacInsightConsent(defaults: defaults).decision == true)
    }

    @Test("the local model never needs consent")
    func localNeedsNoConsent() async {
        let routed = RoutedInsightService(
            local: FixedAnswerInsightService(answer: "Local."), mac: Self.capableMac(FakeLink()), consent: Self.makeConsent()
        )
        #expect(routed.isAvailable)
        #expect(await Self.updates(routed.explain(Self.request)) == [.finished("Local.")])
    }
}

private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
