import Foundation
import NetMonitorCore

/// The heatmap advisor's UI-test seam (#455), for Debug builds launched with `--uitesting`:
/// - `--uitest-insight=answer` answers with `HeatmapAdvisorUITestFixture.answer`;
///   `=unavailable` is never available.
/// - `--seed-heatmap-survey` opens the Wi-Fi Heatmap tool on the finished weak-corner survey,
///   on the Analyze sidebar where the advisor shows.
///
/// Everything else, and every release build, gets nil and false.
@MainActor
enum UITestHeatmapAdvisor {
    /// The advisor's stand-in model, or nil for the on-device model.
    static var insightService: (any InsightServiceProtocol)? {
        #if DEBUG
        guard arguments.contains("--uitesting") else { return nil }
        switch arguments.first(where: { $0.hasPrefix("--uitest-insight=") })?.dropFirst("--uitest-insight=".count) {
        case "answer": return FixedAnswerInsightService(answer: HeatmapAdvisorUITestFixture.answer)
        case "unavailable": return UnavailableInsightService()
        default: return nil
        }
        #else
        return nil
        #endif
    }

    /// The app opens on the Wi-Fi Heatmap tool.
    static var opensHeatmap: Bool {
        #if DEBUG
        arguments.contains("--uitesting") && arguments.contains("--seed-heatmap-survey")
        #else
        false
        #endif
    }

    /// The survey the first heatmap view model opens with, handed out once.
    static func takeSeededSurvey() -> SurveyProject? {
        #if DEBUG
        guard opensHeatmap, !seedTaken else { return nil }
        seedTaken = true
        return HeatmapAdvisorUITestFixture.project()
        #else
        return nil
        #endif
    }

    /// The launch arguments; tests replace them.
    static var arguments = ProcessInfo.processInfo.arguments
    private static var seedTaken = false

    /// Forgets that the seed was handed out, for tests.
    static func reset(arguments: [String]) {
        self.arguments = arguments
        seedTaken = false
    }
}
