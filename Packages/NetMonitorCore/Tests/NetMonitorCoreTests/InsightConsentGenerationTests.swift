import Foundation
import Synchronization
import Testing
@testable import NetMonitorCore

/// #635: explanations sent to the Mac run under the consent generation they began with, like the
/// typed-text schemas (#586).
struct InsightConsentGenerationTests {
    /// A stand-in phone link for insight requests. Like `MacConnectionService.sendInsight`, it sends
    /// only while the request's condition holds when the send itself runs; `beforeSend` runs first.
    final class Link: Sendable {
        private let sent = Mutex<[UUID]>([])
        private let beforeSend: (@Sendable () -> Void)?

        init(beforeSend: (@Sendable () -> Void)? = nil) {
            self.beforeSend = beforeSend
        }

        var requestIDs: [UUID] { sent.withLock { $0 } }

        func send(_ message: CompanionMessage, _ isWanted: @Sendable () -> Bool) -> Bool {
            beforeSend?()
            guard isWanted(), case .insightRequest(let payload) = message else { return false }
            sent.withLock { $0.append(payload.requestID) }
            return true
        }
    }

    private static let request = InsightRequest(subject: "s", facts: ["f"])

    private static func routed(_ link: Link, consent: MacInsightConsent) -> (RoutedInsightService, CompanionInsightClient) {
        let client = CompanionInsightClient(sendIf: { message, isWanted in link.send(message, isWanted) }, timeout: .seconds(30))
        client.received(heartbeat: HeartbeatPayload(capabilities: [CompanionCapability.insight]))
        return (RoutedInsightService(local: UnavailableInsightService(), mac: client, consent: consent), client)
    }

    private static func collect(_ stream: AsyncStream<InsightUpdate>) async -> [InsightUpdate] {
        var updates: [InsightUpdate] = []
        for await update in stream {
            updates.append(update)
        }
        return updates
    }

    @Test("consent withdrawn between the client's check and the send itself: nothing is sent")
    func withdrawnAtTheSend() async {
        let consent = MacInsightConsent(defaults: nil, decision: true)
        let link = Link(beforeSend: { consent.setAllowed(false) })
        let (service, _) = Self.routed(link, consent: consent)
        #expect(await Self.collect(service.explain(Self.request)) == [.unreachable])
        #expect(link.requestIDs.isEmpty)
    }

    @Test("withdrawing consent ends an explanation in flight at once")
    func withdrawalEndsAtOnce() async {
        let consent = MacInsightConsent(defaults: nil, decision: true)
        let link = Link()
        let (service, _) = Self.routed(link, consent: consent)
        let started = ContinuousClock.now
        let updates = Task { await Self.collect(service.explain(Self.request)) }
        await waitForModel { !link.requestIDs.isEmpty }
        consent.setAllowed(false)
        #expect(await updates.value == [.unreachable])
        #expect(ContinuousClock.now - started < .seconds(3), "not left to its 30 s timeout")
    }

    @Test("withdrawn and given again before the answer: the late answer is dropped")
    func lateAnswerDropped() async throws {
        let consent = MacInsightConsent(defaults: nil, decision: true)
        let link = Link()
        let (service, client) = Self.routed(link, consent: consent)
        let updates = Task { await Self.collect(service.explain(Self.request)) }
        await waitForModel { !link.requestIDs.isEmpty }
        let id = try #require(link.requestIDs.first)
        consent.setAllowed(false)
        consent.setAllowed(true)
        client.received(InsightResponsePayload(requestID: id, answer: "Written for the old consent."))
        #expect(await updates.value == [.unreachable])
    }

    @Test("the withdrawal handler is removed however the explanation ends (#642 final check)")
    func handlerAlwaysRemoved() async throws {
        let consent = MacInsightConsent(defaults: nil, decision: true)
        let link = Link()
        let (service, client) = Self.routed(link, consent: consent)
        // Ends with an answer.
        let answered = Task { await Self.collect(service.explain(Self.request)) }
        await waitForModel { !link.requestIDs.isEmpty }
        try client.received(InsightResponsePayload(requestID: #require(link.requestIDs.first), answer: "Fine."))
        _ = await answered.value
        await waitForModel { consent.withdrawalHandlerCount == 0 }
        #expect(consent.withdrawalHandlerCount == 0)
        // Ends with a withdrawal.
        let withdrawn = Task { await Self.collect(service.explain(Self.request)) }
        await waitForModel { link.requestIDs.count == 2 }
        consent.setAllowed(false)
        _ = await withdrawn.value
        await waitForModel { consent.withdrawalHandlerCount == 0 }
        #expect(consent.withdrawalHandlerCount == 0)
    }
}
