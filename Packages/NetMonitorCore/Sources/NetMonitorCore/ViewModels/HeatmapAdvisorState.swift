import Foundation
import Observation

/// The heatmap advisor card on both apps (#455). Shows the app's key points about a finished
/// survey word for word, and the on-device model's paragraph when it is available and its
/// answer passes `InsightSummarizer`'s checks and `HeatmapAdvisorRequest.accepts(_:)`.
///
/// Nothing is shown or asked while a survey is measuring. The model is asked once per survey:
/// the same points on the same plan reuse the last outcome (`ChangeBriefState`).
@MainActor
@Observable
public final class HeatmapAdvisorState {
    public enum Phase: Equatable, Sendable {
        /// No card: nothing measured yet, or a survey is in progress.
        case hidden
        /// Too little to judge; the hint is the app's.
        case sparse(hint: String)
        /// The app's key points, and the model's paragraph or nil when there is none.
        case advice(keyPoints: [String], text: String?)
    }

    /// What the advice is computed from. Both apps' views refresh the advisor whenever it changes
    /// (`.task(id:)`); the plan image is left out of the comparison, so comparing is cheap.
    public struct Input: Equatable, Sendable {
        public let points: [MeasurementPoint]
        public let floorPlan: FloorPlan?
        /// Device display names by normalized MAC (`HeatmapSurveyStatistics.accessPointNames(_:)`).
        public let accessPointNames: [String: String]
        /// A survey is running or a point is being measured.
        public let isSurveying: Bool

        public init(points: [MeasurementPoint], floorPlan: FloorPlan?, accessPointNames: [String: String] = [:], isSurveying: Bool) {
            self.points = points
            self.floorPlan = floorPlan
            self.accessPointNames = accessPointNames
            self.isSurveying = isSurveying
        }

        /// The input for `survey` as it stands: all its points, whatever AP filter the heatmap shows.
        @MainActor
        public init(survey: HeatmapSurveyState, accessPointNames: [String: String] = [:]) {
            self.init(
                points: survey.measurementPoints,
                floorPlan: survey.surveyProject?.floorPlan,
                accessPointNames: accessPointNames,
                isSurveying: survey.isSurveying || survey.isMeasuring
            )
        }

        public static func == (lhs: Input, rhs: Input) -> Bool {
            lhs.isSurveying == rhs.isSurveying && lhs.sameSurvey(as: rhs)
        }

        /// The same points, names and plan, ignoring whether a survey is running.
        func sameSurvey(as other: Input) -> Bool {
            points == other.points && accessPointNames == other.accessPointNames
                && floorPlan?.id == other.floorPlan?.id && floorPlan?.roomLabels == other.floorPlan?.roomLabels
                && floorPlan?.widthMeters == other.floorPlan?.widthMeters && floorPlan?.heightMeters == other.floorPlan?.heightMeters
        }
    }

    public private(set) var phase: Phase = .hidden

    private let brief: ChangeBriefState
    private let configuration: HeatmapRenderer.Configuration
    private var computed: (input: Input, advice: HeatmapAdvice)?
    /// Counts refreshes, so an older one that finishes late doesn't overwrite a newer one.
    private var generation = 0

    public init(
        service: any InsightServiceProtocol,
        timeout: Duration = ChangeBriefState.timeout,
        configuration: HeatmapRenderer.Configuration = .init()
    ) {
        brief = ChangeBriefState(service: service, timeout: timeout)
        self.configuration = configuration
    }

    /// Recomputes the advice for `input` and asks the model about it, unless a survey is running,
    /// which hides the card.
    public func refresh(_ input: Input) async {
        generation += 1
        let current = generation
        guard !input.isSurveying, !input.points.isEmpty else {
            phase = .hidden
            return
        }
        let advice: HeatmapAdvice
        if let computed, computed.input.sameSurvey(as: input) {
            advice = computed.advice
        } else {
            // Interpolating the grid takes a moment; keep it off the main actor.
            let configuration = configuration
            advice = await Task.detached {
                HeatmapAdvisorBuilder.advice(points: input.points, floorPlan: input.floorPlan,
                                             accessPointNames: input.accessPointNames, configuration: configuration)
            }.value
            guard current == generation, !Task.isCancelled else { return }
            computed = (input, advice)
        }
        switch advice {
        case let .sparse(hint):
            phase = .sparse(hint: hint)
        case let .ready(advisor):
            phase = .advice(keyPoints: advisor.keyPoints, text: nil)
            await brief.ask(advisor.request)
            guard current == generation else { return }
            let text = brief.brief.flatMap { advisor.accepts($0.text) ? $0.text : nil }
            phase = .advice(keyPoints: advisor.keyPoints, text: text)
        }
    }
}
