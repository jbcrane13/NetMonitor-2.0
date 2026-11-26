import Foundation
import Testing
@testable import NetMonitorCore

/// #606: a state object starts its model call from a task, so under load a test can send an
/// answer before the request exists. That used to crash with "Index out of range".
@Suite("MockInsightService")
struct MockInsightServiceTests {
    private let request = InsightRequest(subject: "Network", facts: ["Devices: 1"], observations: [])

    /// Every update until the stream finishes, or nil if it hasn't finished after `seconds`: a dropped
    /// final update fails the test at once instead of hanging it.
    private func updates(of stream: AsyncStream<InsightUpdate>, within seconds: Double = 5) async -> [InsightUpdate]? {
        await withTaskGroup(of: [InsightUpdate]?.self) { group in
            group.addTask {
                var received: [InsightUpdate] = []
                for await update in stream {
                    received.append(update)
                }
                return Task.isCancelled ? nil : received
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first.flatMap { $0 }
        }
    }

    @Test func anAnswerSentBeforeTheRequestIsDeliveredWhenItArrives() async {
        let service = MockInsightService()
        service.send(.finished("Early answer."), to: 0)

        let received = await updates(of: service.explain(request))
        #expect(received == [.finished("Early answer.")], "the stream should deliver the early answer and finish")
    }

    @Test func anAnswerSentAfterTheRequestIsDelivered() async {
        let service = MockInsightService()
        let stream = service.explain(request)
        service.send(.finished("Answer."), to: 0)

        let received = await updates(of: stream)
        #expect(received == [.finished("Answer.")], "the stream should deliver the answer and finish")
    }

    @Test func aStreamThatNeverFinishesFailsWithinTheDeadline() async {
        let service = MockInsightService()
        let received = await updates(of: service.explain(request), within: 0.2)
        #expect(received == nil)
    }
}
