import Testing
import Foundation
@testable import NetMonitorCore

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

    @Test("a view reading the affordance hears when a Mac starts or stops offering insight (#457)")
    func availabilityChangesAreObserved() {
        let client = CompanionInsightClient(send: { _ in true })
        let state = ToolInsightState(service: RoutedInsightService(local: UnavailableInsightService(), mac: client))
        let insight = HeartbeatPayload(capabilities: [CompanionCapability.insight])
        let changes = ChangeCounter()
        func track() {
            withObservationTracking { _ = state.isAvailable } onChange: { changes.increment() }
        }

        track()
        client.received(heartbeat: insight)
        #expect(changes.count == 1)
        #expect(state.isAvailable)

        // A repeated heartbeat changes nothing, so nothing redraws.
        track()
        client.received(heartbeat: insight)
        #expect(changes.count == 1)

        client.received(heartbeat: HeartbeatPayload())
        #expect(changes.count == 2)

        client.received(heartbeat: insight)
        track()
        client.disconnected()
        #expect(changes.count == 3)
        #expect(!state.isAvailable)
    }

    @Test("an explanation the Mac writes is marked as the Mac's; a local one as this device's (#457)")
    func explanationRecordsItsSource() async {
        let client = CompanionInsightClient(send: { _ in true })
        client.received(heartbeat: HeartbeatPayload(capabilities: [CompanionCapability.insight]))
        let viaMac = ToolInsightState(service: RoutedInsightService(local: UnavailableInsightService(), mac: client))
        viaMac.explain(request)
        #expect(viaMac.source == .mac)
        client.disconnected()

        let local = ToolInsightState(service: FixedAnswerInsightService(answer: "Your download is fast."))
        await local.explain(request).value
        #expect(local.source == .device)
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

    @Test func anExplanationIsShownOnlyForTheResultItDescribes() async {
        let service = MockInsightService()
        let state = ToolInsightState(service: service)
        let task = state.explain(request)
        await until { !service.requests.isEmpty }
        service.send(.finished("Your download is fast."))
        await task.value

        let newer = InsightRequest(subject: "Internet speed test", facts: ["Download: 4.0 Mbps"])
        #expect(state.phase(for: request) == .finished("Your download is fast."))
        #expect(state.phase(for: newer) == .idle)
    }

    @Test func theUnavailableServiceIsNeverAvailableAndFailsARequest() async {
        let service = UnavailableInsightService()
        #expect(!service.isAvailable)
        var updates: [InsightUpdate] = []
        for await update in service.explain(request) {
            updates.append(update)
        }
        #expect(updates == [.failed])
    }
}

private struct EndsEarlyInsightService: InsightServiceProtocol {
    let isAvailable = true
    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { $0.finish() }
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? {
        nil
    }
}

private final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}
