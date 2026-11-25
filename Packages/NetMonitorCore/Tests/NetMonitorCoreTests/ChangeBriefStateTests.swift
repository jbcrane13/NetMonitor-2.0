import Testing
import Foundation
@testable import NetMonitorCore

/// The ask-once-per-digest engine behind both apps' "since yesterday" briefs (#453, #491 S6).
@Suite("ChangeBriefState")
@MainActor
struct ChangeBriefStateTests {
    static let answer = "A camera joined the network."

    func request(_ observation: String = "1 device joined the network.") -> InsightRequest {
        InsightRequest(subject: "Network changes in the last 24 hours", facts: ["Devices joined: 1", "Joined: Camera"],
                       observations: [observation], kind: .summary)
    }

    /// Asks about `request`, answers the `index`th request with `update`, and waits.
    func ask(_ state: ChangeBriefState, _ insight: MockInsightService, _ request: InsightRequest?, network: UUID? = nil,
             answering update: InsightUpdate, index: Int = 0) async {
        let task = Task { await state.ask(request, network: network) }
        await waitUntil { insight.requests.count > index }
        insight.send(update, to: index)
        await task.value
    }

    @Test func anAnswerShowsTheKeyPointsAndTheText() async {
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)

        await ask(state, insight, request(), answering: .finished(Self.answer))

        #expect(state.brief == ChangeSummary(keyPoints: ["1 device joined the network."], text: Self.answer))
    }

    @Test func theSameDigestIsNotAskedAgain() async {
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)
        await ask(state, insight, request(), answering: .finished(Self.answer))

        await state.ask(request())

        #expect(insight.requests.count == 1)
        #expect(state.brief?.text == Self.answer)
    }

    @Test func theSameDigestIsNotAskedWhileItsAnswerIsPending() async {
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)
        let first = Task { await state.ask(request()) }
        await waitUntil { insight.requests.count == 1 }

        await state.ask(request())
        insight.send(.finished(Self.answer))
        await first.value

        #expect(insight.requests.count == 1)
        #expect(state.brief?.text == Self.answer)
    }

    @Test func noDigestHidesTheBriefWithoutAsking() async {
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)
        await ask(state, insight, request(), answering: .finished(Self.answer))

        await state.ask(nil)

        #expect(state.brief == nil)
        #expect(insight.requests.count == 1)
    }

    @Test func aFailedAnswerHidesTheBriefAndIsNotRetried() async {
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)
        await ask(state, insight, request(), answering: .failed)

        await state.ask(request())

        #expect(state.brief == nil)
        #expect(insight.requests.count == 1)
    }

    @Test func aCancelledAskIsAskedAgain() async {
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)
        let first = Task { await state.ask(request()) }
        await waitUntil { insight.requests.count == 1 }
        first.cancel()
        await first.value

        await ask(state, insight, request(), answering: .finished(Self.answer), index: 1)

        #expect(insight.requests.count == 2)
        #expect(state.brief?.text == Self.answer)
    }

    @Test func aNewerDigestsAnswerDecides() async {
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)
        let older = Task { await state.ask(request()) }
        await waitUntil { insight.requests.count == 1 }

        await ask(state, insight, request("2 devices joined the network."), answering: .finished("Two devices joined the network."), index: 1)
        insight.send(.finished(Self.answer), to: 0)
        await older.value

        #expect(state.brief?.text == "Two devices joined the network.")
    }

    @Test func aDifferentDigestHidesTheShownBriefWhileItIsAsked() async {
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)
        await ask(state, insight, request(), answering: .finished(Self.answer))

        let next = Task { await state.ask(request("2 devices joined the network.")) }
        await waitUntil { insight.requests.count == 2 }

        #expect(state.brief == nil)
        insight.send(.finished("Two devices joined the network."), to: 1)
        await next.value
        #expect(state.brief?.text == "Two devices joined the network.")
    }

    @Test func aBriefAboutAnotherNetworkIsHidden() async {
        let (home, cabin) = (UUID(), UUID())
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)
        await ask(state, insight, request(), network: home, answering: .finished(Self.answer))

        state.keepOnly(network: home)
        #expect(state.brief?.text == Self.answer)
        state.keepOnly(network: cabin)
        #expect(state.brief == nil)
    }

    @Test func hideClearsTheBrief() async {
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)
        await ask(state, insight, request(), answering: .finished(Self.answer))

        state.hide()

        #expect(state.brief == nil)
    }

    @Test("hiding forgets what was asked, so the same digest is asked again once the model is back (#457)")
    func theSameDigestIsAskedAgainAfterHide() async {
        let insight = MockInsightService()
        let state = ChangeBriefState(service: insight)
        await ask(state, insight, request(), answering: .finished(Self.answer))

        state.hide()
        await ask(state, insight, request(), answering: .finished(Self.answer), index: 1)

        #expect(insight.requests.count == 2)
        #expect(state.brief?.text == Self.answer)
    }

    @Test("a digest asked about while no model was available is asked once one is (#457)")
    func anAskWithNoModelIsNotRemembered() async {
        let insight = MockInsightService(isAvailable: false)
        let state = ChangeBriefState(service: insight)
        await state.ask(request())
        #expect(state.brief == nil)
        #expect(insight.requests.isEmpty)

        insight.isAvailable = true
        await ask(state, insight, request(), answering: .finished(Self.answer))

        #expect(state.brief?.text == Self.answer)
    }

    @Test func theFixedAnswerServiceAnswersEveryRequest() async {
        let service = FixedAnswerInsightService(answer: Self.answer)
        var answers: [InsightUpdate] = []
        for await update in service.explain(request()) {
            answers.append(update)
        }
        #expect(service.isAvailable)
        #expect(answers == [.finished(Self.answer)])
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
