import Foundation
import Synchronization
import Testing
@testable import NetMonitorCore

/// Transient and lasting outcomes, and waits long enough for a Mac (#457 review).
@Suite(.serialized)
struct InsightOutcomeTests {
    private static let request = InsightRequest(subject: "Changes since yesterday", facts: ["One device joined"], kind: .summary)

    /// A Mac the user agreed to use, answering each request with the next reply after `delay`.
    private static func scriptedMac(
        delay: Duration = .zero,
        replies: [@Sendable (UUID) -> InsightResponsePayload]
    ) -> (RoutedInsightService, AskCount) {
        let asked = AskCount()
        let box = Mutex<CompanionInsightClient?>(nil)
        let client = CompanionInsightClient(send: { message in
            guard case let .insightRequest(payload) = message, let client = box.withLock({ $0 }) else { return false }
            let index = asked.next()
            Task {
                try? await Task.sleep(for: delay)
                client.received(replies[min(index, replies.count - 1)](payload.requestID))
            }
            return true
        })
        box.withLock { $0 = client }
        client.received(heartbeat: HeartbeatPayload(capabilities: [CompanionCapability.insight]))
        let routed = RoutedInsightService(
            local: UnavailableInsightService(), mac: client, consent: .agreedInMemory
        )
        return (routed, asked)
    }

    @Test("a busy Mac is try-later, a refusal is lasting, and an answer says it came from the Mac")
    func outcomesClassified() async {
        let (busy, _) = Self.scriptedMac(replies: [{ InsightResponsePayload(requestID: $0, failure: .busy) }])
        #expect(await InsightSummarizer.outcome(for: Self.request, service: busy, timeout: .seconds(5)) == .tryLater)

        let (refusing, _) = Self.scriptedMac(replies: [{ InsightResponsePayload(requestID: $0, failure: .refused) }])
        #expect(await InsightSummarizer.outcome(for: Self.request, service: refusing, timeout: .seconds(5)) == .refused)

        let (answering, _) = Self.scriptedMac(replies: [{ InsightResponsePayload(requestID: $0, answer: "One device joined.") }])
        #expect(await InsightSummarizer.outcome(for: Self.request, service: answering, timeout: .seconds(5))
            == .answer(InsightAnswer(text: "One device joined.", source: .mac)))
    }

    @Test("a model that isn't there now is try-later; the local model's answer is marked as this device's")
    func localOutcomes() async {
        #expect(await InsightSummarizer.outcome(for: Self.request, service: UnavailableInsightService(), timeout: .seconds(1)) == .tryLater)
        #expect(await InsightSummarizer.outcome(for: Self.request, service: FixedAnswerInsightService(answer: "One device joined."),
                                                timeout: .seconds(1))
            == .answer(InsightAnswer(text: "One device joined.", source: .device)))
    }

    @Test("after a busy Mac the brief asks again; after a refusal it doesn't")
    @MainActor
    func briefRetriesOnlyTransientFailures() async {
        let (routed, asked) = Self.scriptedMac(replies: [
            { InsightResponsePayload(requestID: $0, failure: .busy) },
            { InsightResponsePayload(requestID: $0, answer: "One device joined.") }
        ])
        let state = ChangeBriefState(service: routed)

        await state.ask(Self.request)
        #expect(state.brief == nil)
        await state.ask(Self.request)
        #expect(state.brief?.text == "One device joined.")
        #expect(state.brief?.source == .mac)
        #expect(asked.value == 2)

        let (refusing, refusedAsked) = Self.scriptedMac(replies: [{ InsightResponsePayload(requestID: $0, failure: .refused) }])
        let refused = ChangeBriefState(service: refusing)
        await refused.ask(Self.request)
        await refused.ask(Self.request)
        #expect(refusedAsked.value == 1)
    }

    @Test("waits through a Mac outlast the Mac's own limit and the phone client's")
    @MainActor
    func macWaitConstants() {
        #expect(InsightSummarizer.macWait > CompanionInsightResponder.defaultTimeout)
        #expect(InsightSummarizer.macWait > CompanionInsightClient.defaultTimeout)
        #expect(ChangeBriefState.timeout < CompanionInsightResponder.defaultTimeout)
    }

    @Test("a Mac answer that takes 17 s still reaches the dashboard brief, whose own wait is 15 s")
    @MainActor
    func slowMacAnswerArrives() async {
        let (routed, _) = Self.scriptedMac(delay: .seconds(17), replies: [
            { InsightResponsePayload(requestID: $0, answer: "One device joined.") }
        ])
        let state = ChangeBriefState(service: routed)

        await state.ask(Self.request)

        #expect(state.brief?.text == "One device joined.")
    }
}

/// Counts the requests a scripted Mac was asked.
final class AskCount: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    /// The index of this request.
    func next() -> Int {
        count.withLock { count in
            defer { count += 1 }
            return count
        }
    }
}
