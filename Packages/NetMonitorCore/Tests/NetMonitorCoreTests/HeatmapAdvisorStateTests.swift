import Testing
import Foundation
@testable import NetMonitorCore

/// The heatmap advisor card's state on both apps (#455): key points from the app, the model's
/// paragraph when it is available, asked once per survey and never while measuring.
@Suite("HeatmapAdvisorState")
@MainActor
struct HeatmapAdvisorStateTests {
    static let answer = "The north-east corner is weak, so try moving the access point toward it."
    static let plan = FloorPlan(imageData: Data(), widthMeters: 10, heightMeters: 8, pixelWidth: 100, pixelHeight: 80)
    static let small = HeatmapRenderer.Configuration(gridWidth: 40, gridHeight: 40)

    /// 25 points on a 5 × 5 lattice, weak in the north-east corner.
    static let weakCorner: [MeasurementPoint] = stride(from: 0.0, through: 1.0, by: 0.25).flatMap { y in
        stride(from: 0.0, through: 1.0, by: 0.25).map { x in
            MeasurementPoint(floorPlanX: x, floorPlanY: y, rssi: x >= 0.75 && y <= 0.25 ? -84 : -52)
        }
    }

    func state(_ service: any InsightServiceProtocol) -> HeatmapAdvisorState {
        HeatmapAdvisorState(service: service, configuration: Self.small)
    }

    func keyPoints(_ state: HeatmapAdvisorState) -> [String] {
        if case let .advice(keyPoints, _) = state.phase {
            return keyPoints
        }
        return []
    }

    @Test func aFinishedSurveyShowsTheKeyPointsAndTheModelsText() async {
        let advisor = state(FixedAnswerInsightService(answer: Self.answer))

        await advisor.refresh(points: Self.weakCorner, floorPlan: Self.plan, isSurveying: false)

        guard case let .advice(keyPoints, text) = advisor.phase else {
            Issue.record("expected advice, got \(advisor.phase)")
            return
        }
        #expect(keyPoints.first?.hasPrefix("The north-east corner is weak (") == true)
        #expect(keyPoints.last == "Try moving the access point toward the north-east corner.")
        #expect(text == Self.answer)
    }

    @Test func anUnavailableModelLeavesTheKeyPointsWithoutText() async {
        let insight = MockInsightService(isAvailable: false)
        let advisor = state(insight)

        await advisor.refresh(points: Self.weakCorner, floorPlan: Self.plan, isSurveying: false)

        guard case let .advice(keyPoints, text) = advisor.phase else {
            Issue.record("expected advice, got \(advisor.phase)")
            return
        }
        #expect(!keyPoints.isEmpty)
        #expect(text == nil)
        #expect(insight.requests.isEmpty)
    }

    @Test func anUngroundedAnswerIsDroppedButTheKeyPointsStay() async {
        let advisor = state(FixedAnswerInsightService(answer: "About 40% of the house is weak."))

        await advisor.refresh(points: Self.weakCorner, floorPlan: Self.plan, isSurveying: false)

        #expect(!keyPoints(advisor).isEmpty)
        #expect(advisor.phase == .advice(keyPoints: keyPoints(advisor), text: nil))
    }

    @Test func theSameSurveyIsAskedOnce() async {
        let insight = MockInsightService()
        let advisor = state(insight)
        let first = Task { await advisor.refresh(points: Self.weakCorner, floorPlan: Self.plan, isSurveying: false) }
        await waitUntil { insight.requests.count == 1 }
        insight.send(.finished(Self.answer))
        await first.value

        await advisor.refresh(points: Self.weakCorner, floorPlan: Self.plan, isSurveying: false)

        #expect(insight.requests.count == 1)
        if case let .advice(_, text) = advisor.phase {
            #expect(text == Self.answer)
        } else {
            Issue.record("expected advice")
        }
    }

    @Test func nothingIsShownOrAskedWhileSurveying() async {
        let insight = MockInsightService()
        let advisor = state(insight)

        await advisor.refresh(points: Self.weakCorner, floorPlan: Self.plan, isSurveying: true)

        #expect(advisor.phase == .hidden)
        #expect(insight.requests.isEmpty)
    }

    @Test func resumingASurveyHidesTheAdvice() async {
        let advisor = state(FixedAnswerInsightService(answer: Self.answer))
        await advisor.refresh(points: Self.weakCorner, floorPlan: Self.plan, isSurveying: false)

        await advisor.refresh(points: Self.weakCorner, floorPlan: Self.plan, isSurveying: true)

        #expect(advisor.phase == .hidden)
    }

    @Test func aSparseSurveyShowsTheHintWithoutAsking() async {
        let insight = MockInsightService()
        let advisor = state(insight)

        await advisor.refresh(points: Array(Self.weakCorner.prefix(6)), floorPlan: Self.plan, isSurveying: false)

        #expect(advisor.phase == .sparse(hint: "Survey at least 10 points with a Wi-Fi signal reading to get advice. This survey has 6."))
        #expect(insight.requests.isEmpty)
    }

    @Test func noMeasurementsShowNothing() async {
        let advisor = state(MockInsightService())

        await advisor.refresh(points: [], floorPlan: Self.plan, isSurveying: false)

        #expect(advisor.phase == .hidden)
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// The survey and answer the apps' UI tests show (#455).
@Suite("HeatmapAdvisorFixture")
@MainActor
struct HeatmapAdvisorFixtureTests {
    @Test func theFixtureShowsAWeakNorthEastCornerAndTheStandInAnswer() async {
        let project = HeatmapAdvisorFixture.project()
        let advisor = HeatmapAdvisorState(service: FixedAnswerInsightService(answer: HeatmapAdvisorFixture.answer))

        await advisor.refresh(points: project.measurementPoints, floorPlan: project.floorPlan, isSurveying: false)

        guard case let .advice(keyPoints, text) = advisor.phase else {
            Issue.record("expected advice, got \(advisor.phase)")
            return
        }
        #expect(keyPoints.first?.hasPrefix("The north-east corner is weak (") == true)
        #expect(text == HeatmapAdvisorFixture.answer)
        #expect(project.floorPlan.imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}
