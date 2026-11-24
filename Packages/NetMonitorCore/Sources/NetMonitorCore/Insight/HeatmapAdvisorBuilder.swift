import Foundation

/// What the heatmap advisor shows for a survey (#455).
public enum HeatmapAdvice: Sendable, Equatable {
    /// Too little to judge: a hint the app writes, and nothing for the model.
    case sparse(hint: String)
    /// The summary request: statistics as facts, the app's judgements and action as key points.
    case ready(InsightRequest)
}

/// Builds the heatmap advisor's summary request (#455). Pure, like `ReportSummaryBuilder`: every
/// figure comes from `HeatmapSurveyStatistics`, and the app picks the action. The model only
/// words the key points and facts.
public enum HeatmapAdvisorBuilder {
    /// Fewest measurements with a signal reading a survey needs before it gets advice.
    public static let minimumPoints = 10
    /// What both apps record as the RSSI when a measurement had no signal reading (no Wi-Fi
    /// Shortcut on iOS, not associated on the Mac). Such points say nothing about coverage.
    public static let noReadingRSSI = -100
    /// Under this share of weak area, in percent, no change is suggested.
    public static let negligibleWeakPercent = 5
    /// A weak region of at least this share, in percent, is too large to fix by moving the access
    /// point: an access point or mesh node is suggested instead.
    public static let addNodeRegionPercent = 25
    /// One access point counts as carrying the survey when it was strongest at this share of points.
    public static let dominantAccessPointPercent = 80

    /// The advice for a survey of `points` on `floorPlan`.
    /// - Parameter accessPointNames: device display names by normalized MAC
    ///   (`HeatmapSurveyStatistics.accessPointNames(_:)`).
    public static func advice(
        points: [MeasurementPoint],
        floorPlan: FloorPlan?,
        accessPointNames: [String: String] = [:],
        configuration: HeatmapRenderer.Configuration = .init()
    ) -> HeatmapAdvice {
        guard let floorPlan else {
            return .sparse(hint: "Load a floor plan and survey at least \(minimumPoints) points with a Wi-Fi signal reading to get advice.")
        }
        let readings = points.filter { $0.rssi > noReadingRSSI }
        guard readings.count >= minimumPoints else {
            return .sparse(
                hint: "Survey at least \(minimumPoints) points with a Wi-Fi signal reading to get advice. This survey has \(readings.count)."
            )
        }
        let stats = HeatmapSurveyStatistics(
            points: readings,
            roomLabels: floorPlan.roomLabels ?? [],
            accessPointNames: accessPointNames,
            configuration: configuration
        )
        return .ready(request(stats))
    }

    /// The summary request for `stats`.
    public static func request(_ stats: HeatmapSurveyStatistics) -> InsightRequest {
        let good = Int(HeatmapSurveyStatistics.goodRSSI), fair = Int(HeatmapSurveyStatistics.fairRSSI)
        var facts = [
            "Measured points: \(stats.pointCount)",
            "Area with good signal (\(good) dBm or better): \(stats.coverage.good)%",
            "Area with fair signal (\(fair) to \(good) dBm): \(stats.coverage.fair)%",
            "Area with weak signal (below \(fair) dBm): \(stats.coverage.weak)%",
            "Weak areas: \(stats.weakRegions.count)"
        ]
        for (index, region) in stats.weakRegions.enumerated() {
            facts.append("Weak area \(index + 1): \(region.location.phrase), \(region.areaPercent)% of the area, "
                + "worst \(region.worstRSSI) dBm, average \(region.meanRSSI) dBm")
        }
        if let falloff = stats.falloff {
            facts.append("Signal falls off toward the \(falloff.rawValue)")
        }
        if !stats.accessPoints.isEmpty {
            facts.append("Access points: \(stats.accessPoints.count)")
            facts += stats.accessPoints.map { "\($0.name): strongest at \($0.pointPercent)% of points" }
        }
        return InsightRequest(subject: "Wi-Fi heatmap survey", facts: facts, observations: observations(stats), kind: .summary)
    }

    // MARK: - Judgements

    private static func observations(_ stats: HeatmapSurveyStatistics) -> [String] {
        guard stats.coverage.weak >= negligibleWeakPercent, let largest = stats.weakRegions.first else {
            return ["Little of the surveyed area is weak, so no change is needed."]
        }
        // One key point per place: the largest region there stands for the others, which stay in the facts.
        var places = Set<String>()
        var points = stats.weakRegions.filter { places.insert($0.location.phrase).inserted }.map { region in
            sentence("\(region.location.phrase) is weak (\(region.areaPercent)% of the area, worst \(region.worstRSSI) dBm).")
        }
        if stats.accessPoints.count > 1, let top = stats.accessPoints.first, top.pointPercent >= dominantAccessPointPercent {
            points.append("\(top.name) was the strongest access point at \(top.pointPercent)% of points.")
        }
        points.append(largest.areaPercent >= addNodeRegionPercent
            ? "Add an access point or mesh node near \(largest.location.phrase)."
            : "Try moving the access point toward \(largest.location.phrase).")
        return points
    }

    /// `text` with its first letter capitalized.
    private static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
