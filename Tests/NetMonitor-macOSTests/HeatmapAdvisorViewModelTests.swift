import Foundation
import Testing
@testable import NetMonitor_macOS
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

/// The heatmap advisor on the macOS survey result (#455).
@Suite("WiFiHeatmapViewModel advisor")
@MainActor
struct HeatmapAdvisorViewModelTests {
    private func makeVM(_ insight: MockCountingInsightService) -> WiFiHeatmapViewModel {
        let vm = WiFiHeatmapViewModel(insightService: insight, seededSurvey: nil)
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

/// The macOS UI-test seam (#455): `--seed-heatmap-survey` and `--uitest-insight`.
@Suite("UITestHeatmapAdvisor", .serialized)
@MainActor
struct UITestHeatmapAdvisorTests {
    @Test func aSeededSurveyOpensOnTheAnalyzeSidebar() {
        let vm = WiFiHeatmapViewModel(insightService: UnavailableInsightService(), seededSurvey: HeatmapAdvisorUITestFixture.project())

        #expect(vm.surveyProject?.name == HeatmapAdvisorUITestFixture.projectName)
        #expect(vm.measurementPoints.count == 25)
        #expect(vm.isCalibrated)
        #expect(vm.sidebarMode == .analyze)
    }

    @Test func theSeedIsHandedOutOnceAndOnlyWithItsFlags() {
        defer { UITestHeatmapAdvisor.reset(arguments: ProcessInfo.processInfo.arguments) }
        UITestHeatmapAdvisor.reset(arguments: ["--uitesting"])
        #expect(!UITestHeatmapAdvisor.opensHeatmap)
        #expect(UITestHeatmapAdvisor.takeSeededSurvey() == nil)

        UITestHeatmapAdvisor.reset(arguments: ["--uitesting", "--seed-heatmap-survey"])
        #expect(UITestHeatmapAdvisor.opensHeatmap)
        #expect(UITestHeatmapAdvisor.takeSeededSurvey()?.name == HeatmapAdvisorUITestFixture.projectName)
        #expect(UITestHeatmapAdvisor.takeSeededSurvey() == nil)
    }

    @Test func theInsightArgumentPicksTheStandInModel() {
        defer { UITestHeatmapAdvisor.reset(arguments: ProcessInfo.processInfo.arguments) }
        UITestHeatmapAdvisor.reset(arguments: ["--uitesting", "--uitest-insight=answer"])
        #expect(UITestHeatmapAdvisor.insightService?.isAvailable == true)
        UITestHeatmapAdvisor.reset(arguments: ["--uitesting", "--uitest-insight=unavailable"])
        #expect(UITestHeatmapAdvisor.insightService?.isAvailable == false)
        UITestHeatmapAdvisor.reset(arguments: ["--uitest-insight=answer"])
        #expect(UITestHeatmapAdvisor.insightService == nil)
    }
}
