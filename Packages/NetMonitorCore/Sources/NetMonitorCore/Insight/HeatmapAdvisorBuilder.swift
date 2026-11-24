import Foundation

/// What the heatmap advisor shows for a survey (#455).
public enum HeatmapAdvice: Sendable, Equatable {
    /// Too little to judge: a hint the app writes, and nothing for the model.
    case sparse(hint: String)
    /// The app's key points and the request the model words.
    case ready(HeatmapAdvisorRequest)
}

/// The action the app suggests for a survey; the model only words it.
public enum HeatmapAdvisorAction: Sendable, Equatable {
    /// Under `HeatmapAdvisorBuilder.negligibleWeakPercent` of the area is weak.
    case noChange
    /// Enough of the area is weak, but only in specks too small to be a place to target.
    case scattered
    /// One access point (or none known), and the largest weak place is small: move it toward the place.
    case moveAccessPoint(toward: String)
    /// One access point (or none known), and the largest weak place is large: add a node near it.
    case addNode(near: String)
    /// Two or more access points, whose positions the app doesn't know: add a node or move one.
    case addOrMoveNode(toward: String)

    /// The action as the key point the card shows and the model must state.
    public var keyPoint: String {
        switch self {
        case .noChange: "Little of the surveyed area is weak, so no change is needed."
        case .scattered: "No single place is weak enough to target, so no change is suggested."
        case let .moveAccessPoint(place): "Try moving the access point toward \(place)."
        case let .addNode(place): "Add an access point or mesh node near \(place)."
        case let .addOrMoveNode(place): "Add a mesh node or move one toward \(place)."
        }
    }

    /// Whole words or phrases an answer must use, any one of them, to have stated this action.
    var statedBy: [String] {
        let move = ["move", "moving", "moved", "reposition", "repositioning", "relocate", "relocating"]
        let add = ["add", "adding", "added", "mesh"]
        return switch self {
        case .noChange: ["no change", "no changes", "any change", "any changes", "not need", "no need", "nothing needs"]
        case .scattered: ["no single", "scattered", "small patches", "no change", "any change", "any changes"]
        case .moveAccessPoint: move
        case .addNode: add
        case .addOrMoveNode: add + move
        }
    }
}

/// The heatmap advisor's request (#455). The card shows `keyPoints` word for word, with the
/// app's figures for each weak place. The model gets `request`, which names the places but
/// gives none of their figures, so it can't pair a place with another place's value.
public struct HeatmapAdvisorRequest: Sendable, Equatable {
    /// Shown on the card word for word.
    public let keyPoints: [String]
    /// What the model words: overall coverage, place names, access points and the action.
    public let request: InsightRequest
    public let action: HeatmapAdvisorAction
    /// Weak places, in key-point order.
    public let places: [HeatmapSurveyStatistics.Location]
    public let falloff: HeatmapSurveyStatistics.Compass?
    /// Every room label on the plan, computed into a place or not.
    public let planRooms: [String]
}

/// Builds the heatmap advisor's request (#455). Pure, like `ReportSummaryBuilder`: every figure
/// comes from `HeatmapSurveyStatistics`, and the app picks the action. The model only words it.
public enum HeatmapAdvisorBuilder {
    /// Fewest different spots with a signal reading a survey needs before it gets advice.
    public static let minimumPoints = 10
    /// What both apps record as the RSSI when a measurement had no signal reading (no Wi-Fi
    /// Shortcut on iOS, not associated on the Mac). Such points say nothing about coverage.
    public static let noReadingRSSI = -100
    /// Under this share of weak area, in percent, no change is suggested.
    public static let negligibleWeakPercent = 5
    /// A weak place of at least this share, in percent, is too large to fix by moving the one
    /// access point: an access point or mesh node is suggested instead.
    public static let addNodeRegionPercent = 25
    /// One access point counts as carrying the survey when measurements were connected to it at
    /// this share of points.
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
            return .sparse(hint: "Load a floor plan and survey at least \(minimumPoints) different spots with a Wi-Fi signal reading to get advice.")
        }
        let readings = points.filter { $0.rssi > noReadingRSSI }
        // Continuous capture can record one spot many times; a spot counts once.
        let spots = Set(readings.map { [Int(($0.floorPlanX * 100).rounded()), Int(($0.floorPlanY * 100).rounded())] }).count
        guard spots >= minimumPoints else {
            return .sparse(hint: "Survey at least \(minimumPoints) different spots with a Wi-Fi signal reading to get advice. "
                + "This survey has \(spots).")
        }
        let stats = HeatmapSurveyStatistics(
            points: readings,
            floorPlan: floorPlan,
            accessPointNames: accessPointNames,
            configuration: configuration
        )
        guard stats.surveyedCells > 0 else {
            return .sparse(hint: "None of the measured spots is on the plan, so there is nothing to judge yet.")
        }
        return .ready(advice(for: stats, planRooms: (floorPlan.roomLabels ?? []).map(\.text)))
    }

    /// The key points and model request for `stats`.
    /// - Parameter planRooms: every room label on the plan.
    public static func advice(for stats: HeatmapSurveyStatistics, planRooms: [String] = []) -> HeatmapAdvisorRequest {
        // One key point per place: the largest region there stands for the others.
        var seen = Set<String>()
        let regions = stats.weakRegions.filter { seen.insert($0.location.phrase).inserted }
        let action = action(for: stats)
        var keyPoints: [String] = []
        var modelPoints: [String] = []
        if case .scattered = action {
            keyPoints.append("Weak signal covers \(stats.coverage.weak)% of the area in small scattered patches.")
            modelPoints.append("Weak signal is scattered in small patches.")
        } else if action != .noChange {
            for region in regions {
                keyPoints.append(sentence("\(region.location.phrase) is weak (\(region.areaPercent)% of the area, worst \(region.worstRSSI) dBm)."))
                modelPoints.append(sentence("\(region.location.phrase) is weak."))
            }
            if stats.accessPoints.count > 1, let top = stats.accessPoints.first, top.pointPercent >= dominantAccessPointPercent {
                let point = "\(top.name) was the connected access point at \(top.pointPercent)% of points."
                keyPoints.append(point)
                modelPoints.append(point)
            }
        }
        keyPoints.append(action.keyPoint)
        // First for the model, as `.advice` instructions say: an answer without the action is dropped.
        modelPoints.insert(action.keyPoint, at: 0)
        return HeatmapAdvisorRequest(
            keyPoints: keyPoints,
            request: InsightRequest(subject: "Wi-Fi heatmap survey", facts: facts(stats, places: regions), observations: modelPoints, kind: .advice),
            action: action,
            places: regions.map(\.location),
            falloff: stats.falloff,
            planRooms: planRooms
        )
    }

    // MARK: - Judgements

    private static func action(for stats: HeatmapSurveyStatistics) -> HeatmapAdvisorAction {
        guard stats.coverage.weak >= negligibleWeakPercent else { return .noChange }
        guard let largest = stats.weakRegions.first else { return .scattered }
        let place = largest.location.phrase
        if stats.accessPoints.count > 1 {
            return .addOrMoveNode(toward: place)
        }
        return largest.areaPercent >= addNodeRegionPercent ? .addNode(near: place) : .moveAccessPoint(toward: place)
    }

    /// Overall figures and place names only: no figure belongs to one place.
    private static func facts(_ stats: HeatmapSurveyStatistics, places: [HeatmapSurveyStatistics.WeakRegion]) -> [String] {
        let good = Int(HeatmapSurveyStatistics.goodRSSI), fair = Int(HeatmapSurveyStatistics.fairRSSI)
        var facts = [
            "Measured points: \(stats.pointCount)",
            "Area with good signal (\(good) dBm or better): \(stats.coverage.good)%",
            "Area with fair signal (\(fair) to \(good) dBm): \(stats.coverage.fair)%",
            "Area with weak signal (below \(fair) dBm): \(stats.coverage.weak)%",
            "Weak areas: \(stats.weakRegionCount)"
        ]
        if !places.isEmpty {
            facts.append("Weak places: " + places.map(\.location.phrase).joined(separator: ", "))
        }
        if let falloff = stats.falloff {
            facts.append("Signal falls off toward the \(falloff.rawValue)")
        }
        if !stats.accessPoints.isEmpty {
            facts.append("Access points: \(stats.accessPoints.count)")
            facts += stats.accessPoints.map { "\($0.name): connected at \($0.pointPercent)% of points" }
        }
        return facts
    }

    /// `text` with its first letter capitalized.
    private static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
