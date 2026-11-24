import Foundation
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

/// Answers every request with `answer` and counts them.
private final class MockCountingInsightService: InsightServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let isAvailable: Bool
    let answer: String

    init(isAvailable: Bool = true, answer: String = HeatmapAdvisorUITestFixture.answer) {
        self.isAvailable = isAvailable
        self.answer = answer
    }

    var requests: Int { lock.withLock { count } }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        lock.withLock { count += 1 }
        return AsyncStream { continuation in
            continuation.yield(.finished(answer))
            continuation.finish()
        }
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? { nil }
}

/// The heatmap advisor on the iOS survey result (#455).
@Suite("HeatmapSurveyViewModel advisor")
@MainActor
struct HeatmapAdvisorViewModelTests {
    private func makeVM(_ insight: MockCountingInsightService) -> HeatmapSurveyViewModel {
        let vm = HeatmapSurveyViewModel(service: MockHeatmapService(), insightService: insight)
        vm.state.setProject(HeatmapAdvisorUITestFixture.project())
        return vm
    }

    @Test func aFinishedSurveyShowsTheKeyPointsAndTheModelsText() async {
        let vm = makeVM(MockCountingInsightService())

        await vm.advisor.refresh(.init(survey: vm.state))

        guard case let .advice(keyPoints, text) = vm.advisor.phase else {
            Issue.record("expected advice, got \(vm.advisor.phase)")
            return
        }
        #expect(keyPoints.first?.hasPrefix("The north-east corner is weak (") == true)
        #expect(text == HeatmapAdvisorUITestFixture.answer)
    }

    @Test func nothingIsAskedWhileSurveying() async {
        let insight = MockCountingInsightService()
        let vm = makeVM(insight)
        vm.isSurveying = true

        await vm.advisor.refresh(.init(survey: vm.state))

        #expect(vm.advisor.phase == .hidden)
        #expect(insight.requests == 0)
    }

    @Test func nothingIsAskedWhileAPointIsBeingMeasured() async {
        let insight = MockCountingInsightService()
        let vm = makeVM(insight)
        vm.isMeasuring = true

        await vm.advisor.refresh(.init(survey: vm.state))

        #expect(vm.advisor.phase == .hidden)
        #expect(insight.requests == 0)
    }

    @Test func anUnavailableModelShowsOnlyTheKeyPoints() async {
        let insight = MockCountingInsightService(isAvailable: false)
        let vm = makeVM(insight)

        await vm.advisor.refresh(.init(survey: vm.state))

        guard case let .advice(keyPoints, text) = vm.advisor.phase else {
            Issue.record("expected advice, got \(vm.advisor.phase)")
            return
        }
        #expect(!keyPoints.isEmpty)
        #expect(text == nil)
        #expect(insight.requests == 0)
    }

    @Test func theSameSurveyIsAskedOnce() async {
        let insight = MockCountingInsightService()
        let vm = makeVM(insight)

        await vm.advisor.refresh(.init(survey: vm.state))
        await vm.advisor.refresh(.init(survey: vm.state))

        #expect(insight.requests == 1)
    }
}
