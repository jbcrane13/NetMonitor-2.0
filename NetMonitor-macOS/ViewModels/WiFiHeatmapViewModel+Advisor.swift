import Foundation
import NetMonitorCore

// MARK: - Advisor (#455)

extension WiFiHeatmapViewModel {
    /// Recomputes the advisor for the current survey; hidden, and nothing asked, while a survey
    /// runs or a point is being measured.
    /// - Parameter accessPointNames: device display names by normalized MAC.
    func refreshAdvisor(accessPointNames: [String: String] = [:]) async {
        await advisor.refresh(
            points: state.measurementPoints,
            floorPlan: state.surveyProject?.floorPlan,
            accessPointNames: accessPointNames,
            isSurveying: state.isSurveying || state.isMeasuring
        )
    }

    /// The advisor's insight service. Under `--uitesting`, `--uitest-insight=answer` answers with
    /// `HeatmapAdvisorFixture.answer` and `=unavailable` is never available; otherwise the
    /// on-device model.
    static func advisorInsightService(arguments: [String]) -> any InsightServiceProtocol {
        guard arguments.contains("--uitesting") else { return InsightService.shared }
        switch arguments.first(where: { $0.hasPrefix("--uitest-insight=") })?.dropFirst("--uitest-insight=".count) {
        case "answer": return FixedAnswerInsightService(answer: HeatmapAdvisorFixture.answer)
        case "unavailable": return UnavailableInsightService()
        default: return InsightService.shared
        }
    }

    /// `--uitesting --seed-heatmap-survey`: opens the finished weak-corner survey on the Analyze
    /// sidebar, where the advisor shows.
    func seedForUITests(arguments: [String]) {
        guard arguments.contains("--uitesting"), arguments.contains("--seed-heatmap-survey"), surveyProject == nil else { return }
        state.setProject(HeatmapAdvisorFixture.project())
        sidebarMode = .analyze
        generateHeatmap()
    }
}
