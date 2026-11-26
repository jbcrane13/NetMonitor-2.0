import Foundation
import Testing
import NetMonitorCore

/// #606: a state object starts its model call from a task, so under load a test can send an
/// answer before the request exists. That used to crash with "Index out of range".
@Suite("MockInsightService")
struct MockInsightServiceTests {
    private let request = InsightRequest(subject: "Network", facts: ["Devices: 1"], observations: [])

    @Test func anAnswerSentBeforeTheRequestIsDeliveredWhenItArrives() async {
        let service = MockInsightService()
        service.send(.finished("Early answer."), to: 0)

        var updates: [InsightUpdate] = []
        for await update in service.explain(request) {
            updates.append(update)
        }
        #expect(updates == [.finished("Early answer.")])
    }

    @Test func anAnswerSentAfterTheRequestIsDelivered() async {
        let service = MockInsightService()
        let stream = service.explain(request)
        service.send(.finished("Answer."), to: 0)

        var updates: [InsightUpdate] = []
        for await update in stream {
            updates.append(update)
        }
        #expect(updates == [.finished("Answer.")])
    }
}
