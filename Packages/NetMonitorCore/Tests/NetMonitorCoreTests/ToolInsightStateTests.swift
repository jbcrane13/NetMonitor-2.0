import Testing
import Foundation
@testable import NetMonitorCore

/// An insight service the test drives by hand.
final class MockInsightService: InsightServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var available: Bool
    private var continuations: [AsyncStream<InsightUpdate>.Continuation] = []
    private var received: [InsightRequest] = []

    init(isAvailable: Bool = true) {
        available = isAvailable
    }

    var isAvailable: Bool { lock.withLock { available } }
    var requests: [InsightRequest] { lock.withLock { received } }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            lock.withLock {
                received.append(request)
                continuations.append(continuation)
            }
        }
    }

    /// Sends `update` on the stream of the `index`th request.
    func send(_ update: InsightUpdate, to index: Int = 0) {
        let continuation = lock.withLock { continuations[index] }
        continuation.yield(update)
        if case .partial = update {
            return
        }
        continuation.finish()
    }
}

@Suite("ToolInsightState")
@MainActor
struct ToolInsightStateTests {
    let request = InsightRequest(subject: "Internet speed test", facts: ["Download: 412 Mbps"])

    /// Lets the state's task run until `condition` holds.
    func until(_ condition: () -> Bool) async {
        for _ in 0 ..< 1000 where !condition() {
            await Task.yield()
        }
    }

    @Test func affordanceFollowsServiceAvailability() {
        #expect(ToolInsightState(service: MockInsightService(isAvailable: true)).isAvailable)
        #expect(!ToolInsightState(service: MockInsightService(isAvailable: false)).isAvailable)
    }

    @Test func explainingShowsTextAsItArrivesThenTheFinishedText() async {
        let service = MockInsightService()
        let state = ToolInsightState(service: service)
        #expect(state.phase == .idle)

        let task = state.explain(request)
        #expect(state.phase == .generating(""))
        await until { !service.requests.isEmpty }
        #expect(service.requests == [request])

        service.send(.partial("Your download"))
        await until { state.phase == .generating("Your download") }
        #expect(state.phase == .generating("Your download"))

        service.send(.finished("Your download is fast."))
        await task.value
        #expect(state.phase == .finished("Your download is fast."))
    }

    @Test func aFailureIsShownAsFailed() async {
        let service = MockInsightService()
        let state = ToolInsightState(service: service)
        let task = state.explain(request)
        await until { !service.requests.isEmpty }
        service.send(.failed)
        await task.value
        #expect(state.phase == .failed)
    }

    @Test func aStreamThatEndsWithoutAResultIsShownAsFailed() async {
        let state = ToolInsightState(service: EndsEarlyInsightService())
        await state.explain(request).value
        #expect(state.phase == .failed)
    }

    @Test func nothingIsRequestedWhenTheModelIsUnavailable() async {
        let service = MockInsightService(isAvailable: false)
        let state = ToolInsightState(service: service)
        await state.explain(request).value
        #expect(state.phase == .idle)
        #expect(service.requests.isEmpty)
    }

    @Test func resetClearsTheExplanationAndIgnoresLateText() async {
        let service = MockInsightService()
        let state = ToolInsightState(service: service)
        let task = state.explain(request)
        await until { !service.requests.isEmpty }

        state.reset()
        service.send(.finished("Late text"))
        await task.value

        #expect(state.phase == .idle)
    }

    @Test func aSecondExplainReplacesTheFirst() async {
        let service = MockInsightService()
        let state = ToolInsightState(service: service)
        let first = state.explain(request)
        await until { service.requests.count == 1 }
        let second = state.explain(InsightRequest(subject: "WHOIS lookup for example.org", facts: []))
        await until { service.requests.count == 2 }

        service.send(.finished("First"), to: 0)
        service.send(.finished("Second"), to: 1)
        await first.value
        await second.value

        #expect(state.phase == .finished("Second"))
    }
}

private struct EndsEarlyInsightService: InsightServiceProtocol {
    let isAvailable = true
    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { $0.finish() }
    }
}
