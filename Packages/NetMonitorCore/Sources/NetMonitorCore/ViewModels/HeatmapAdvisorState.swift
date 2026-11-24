import Foundation
import Observation

/// The heatmap advisor card on both apps (#455). Shows the app's key points about a finished
/// survey word for word, and the on-device model's paragraph when it is available and its
/// answer passes `InsightSummarizer`'s checks.
///
/// Nothing is shown or asked while a survey is measuring. The model is asked once per survey:
/// the same points on the same plan reuse the last outcome (`ChangeBriefState`).
@MainActor
@Observable
public final class HeatmapAdvisorState {
    public enum Phase: Equatable, Sendable {
        /// No card: nothing measured yet, or a survey is in progress.
        case hidden
        /// Too few points to judge; the hint is the app's.
        case sparse(hint: String)
        /// The app's key points, and the model's paragraph or nil when there is none.
        case advice(keyPoints: [String], text: String?)
    }

    public private(set) var phase: Phase = .hidden

    /// What the advice is computed from; the plan image is left out, so comparing is cheap.
    private struct Survey: Equatable {
        let points: [MeasurementPoint]
        let planID: UUID?
        let roomLabels: [RoomLabel]?
        let accessPointNames: [String: String]
    }

    private let brief: ChangeBriefState
    private let configuration: HeatmapRenderer.Configuration
    private var computed: (survey: Survey, advice: HeatmapAdvice)?
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

    /// Recomputes the advice for a survey of `points` on `floorPlan` and asks the model about it,
    /// unless `isSurveying` (measuring, or a survey still running), which hides the card.
    /// - Parameter accessPointNames: device display names by normalized MAC
    ///   (`HeatmapSurveyStatistics.accessPointNames(_:)`).
    public func refresh(
        points: [MeasurementPoint],
        floorPlan: FloorPlan?,
        accessPointNames: [String: String] = [:],
        isSurveying: Bool
    ) async {
        generation += 1
        let current = generation
        guard !isSurveying, !points.isEmpty else {
            phase = .hidden
            return
        }
        let survey = Survey(points: points, planID: floorPlan?.id, roomLabels: floorPlan?.roomLabels, accessPointNames: accessPointNames)
        let advice: HeatmapAdvice
        if let computed, computed.survey == survey {
            advice = computed.advice
        } else {
            // Interpolating the grid takes a moment; keep it off the main actor.
            let configuration = configuration
            advice = await Task.detached {
                HeatmapAdvisorBuilder.advice(points: points, floorPlan: floorPlan,
                                             accessPointNames: accessPointNames, configuration: configuration)
            }.value
            guard current == generation, !Task.isCancelled else { return }
            computed = (survey, advice)
        }
        switch advice {
        case let .sparse(hint):
            phase = .sparse(hint: hint)
        case let .ready(request):
            phase = .advice(keyPoints: request.observations, text: nil)
            await brief.ask(request)
            guard current == generation else { return }
            phase = .advice(keyPoints: request.observations, text: brief.brief?.text)
        }
    }
}
