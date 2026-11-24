import Testing
import Foundation
@testable import NetMonitorCore

/// The heatmap advisor's request (#455): key points with the app's figures for the card, and a
/// request for the model that names places but gives none of their figures.
@Suite("HeatmapAdvisorBuilder")
struct HeatmapAdvisorBuilderTests {
    typealias Stats = HeatmapSurveyStatistics

    static let plan = FloorPlan(imageData: Data(), widthMeters: 10, heightMeters: 8, pixelWidth: 100, pixelHeight: 80)

    /// A 10 × 10 grid at -50 dBm with weak cells (-84 at the top-right cell, -79 elsewhere) in
    /// the given rows and columns.
    static func stats(weakRows: Range<Int>, weakCols: Range<Int>, accessPoints: [Stats.AccessPointShare] = [],
                      roomLabels: [RoomLabel] = []) -> Stats {
        let grid: [[Double?]] = (0 ..< 10).map { row in
            (0 ..< 10).map { col in
                guard weakRows.contains(row), weakCols.contains(col) else { return -50 }
                return row == 0 && col == 9 ? -84 : -79
            }
        }
        return Stats(grid: grid, pointCount: 24, roomLabels: roomLabels, accessPoints: accessPoints)
    }

    @Test func aSmallWeakCornerSuggestsMovingTheAccessPointTowardIt() {
        // 18 of 100 cells: 3 rows × 6 columns in the north-east.
        let advice = HeatmapAdvisorBuilder.advice(for: Self.stats(weakRows: 0 ..< 3, weakCols: 4 ..< 10))

        #expect(advice.keyPoints == [
            "The north-east corner is weak (18% of the area, worst -84 dBm).",
            "Try moving the access point toward the north-east corner."
        ])
        #expect(advice.action == .moveAccessPoint(toward: "the north-east corner"))
        #expect(advice.request.kind == .advice)
        #expect(advice.request.subject == "Wi-Fi heatmap survey")
        // The action first: the model is told to state it first.
        #expect(advice.request.observations == [
            "Try moving the access point toward the north-east corner.",
            "The north-east corner is weak."
        ])
        #expect(advice.request.facts == [
            "Measured points: 24",
            "Area with good signal (-67 dBm or better): 82%",
            "Area with fair signal (-75 to -67 dBm): 0%",
            "Area with weak signal (below -75 dBm): 18%",
            "Weak areas: 1",
            "Weak places: the north-east corner",
            "Signal falls off toward the north-east"
        ])
    }

    @Test func theModelGetsNoFigureOfAnyOnePlace() {
        let advice = HeatmapAdvisorBuilder.advice(for: Self.stats(weakRows: 0 ..< 3, weakCols: 4 ..< 10))

        let prompt = advice.request.prompt
        #expect(!prompt.contains("-84"))
        #expect(!prompt.contains("-79"))
        // 18% is the overall weak share, which the model may state; no place carries a figure.
        #expect(!advice.request.observations.contains { $0.contains("%") || $0.contains("dBm") })
    }

    @Test func aLargeWeakPlaceSuggestsAddingANode() {
        // 30 of 100 cells.
        let advice = HeatmapAdvisorBuilder.advice(for: Self.stats(weakRows: 0 ..< 3, weakCols: 0 ..< 10))

        #expect(advice.keyPoints.last == "Add an access point or mesh node near the north side.")
        #expect(advice.action == .addNode(near: "the north side"))
    }

    @Test func aWeakPlaceAtTheThresholdSuggestsAddingANode() {
        // 25 of 100 cells: 5 × 5 in the north-west.
        let advice = HeatmapAdvisorBuilder.advice(for: Self.stats(weakRows: 0 ..< 5, weakCols: 0 ..< 5))

        #expect(HeatmapAdvisorBuilder.addNodeRegionPercent == 25)
        #expect(advice.keyPoints.last == "Add an access point or mesh node near the north-west corner.")
    }

    @Test func anAllWeakSurveySuggestsAddingANodeInTheMiddle() {
        let grid: [[Double?]] = Array(repeating: Array(repeating: -85, count: 10), count: 10)

        let advice = HeatmapAdvisorBuilder.advice(for: Stats(grid: grid, pointCount: 24))

        #expect(advice.keyPoints == [
            "The centre is weak (100% of the area, worst -85 dBm).",
            "Add an access point or mesh node near the centre."
        ])
        #expect(advice.request.facts.contains("Area with weak signal (below -75 dBm): 100%"))
        #expect(!advice.request.facts.contains { $0.hasPrefix("Signal falls off") })
    }

    @Test func littleWeakAreaNeedsNoChange() {
        // 4 of 100 cells: under the 5% that needs a change.
        let advice = HeatmapAdvisorBuilder.advice(for: Self.stats(weakRows: 0 ..< 2, weakCols: 8 ..< 10))

        #expect(HeatmapAdvisorBuilder.negligibleWeakPercent == 5)
        #expect(advice.keyPoints == ["Little of the surveyed area is weak, so no change is needed."])
        #expect(advice.request.observations == advice.keyPoints)
        #expect(advice.action == .noChange)
    }

    @Test func aMostlyFairSurveyIsNotCalledGood() {
        // Every cell at -70 dBm: fair, nothing weak.
        let grid: [[Double?]] = Array(repeating: Array(repeating: -70, count: 10), count: 10)

        let advice = HeatmapAdvisorBuilder.advice(for: Stats(grid: grid, pointCount: 24))

        #expect(advice.keyPoints == ["Little of the surveyed area is weak, so no change is needed."])
        #expect(advice.request.facts.contains("Area with fair signal (-75 to -67 dBm): 100%"))
    }

    @Test func weakSpecksWithNoPlaceToTargetAreScattered() {
        // One isolated weak cell in every 3 × 3 block of a 30 × 30 grid: 100 of 900 cells (11%),
        // each 0.1% of the area, too small to be a place.
        let grid: [[Double?]] = (0 ..< 30).map { row in
            (0 ..< 30).map { col in row % 3 == 0 && col % 3 == 0 ? -85 : -50 }
        }

        let advice = HeatmapAdvisorBuilder.advice(for: Stats(grid: grid, pointCount: 24))

        #expect(advice.action == .scattered)
        #expect(advice.keyPoints == [
            "Weak signal covers 11% of the area in small scattered patches.",
            "No single place is weak enough to target, so no change is suggested."
        ])
        #expect(advice.request.facts.contains("Weak areas: 0"))
    }

    @Test func aRoomNameWritesTheKeyPoints() {
        let rooms = [RoomLabel(text: "Kitchen", normalizedX: 0.8, normalizedY: 0.1)]

        let advice = HeatmapAdvisorBuilder.advice(
            for: Self.stats(weakRows: 0 ..< 3, weakCols: 4 ..< 10, roomLabels: rooms), planRooms: ["Kitchen", "Garage"]
        )

        #expect(advice.keyPoints == [
            "The Kitchen is weak (18% of the area, worst -84 dBm).",
            "Try moving the access point toward the Kitchen."
        ])
        #expect(advice.request.facts.contains("Weak places: the Kitchen"))
        #expect(advice.places == [.room("Kitchen")])
        #expect(advice.planRooms == ["Kitchen", "Garage"])
    }

    @Test func twoAccessPointsSuggestAddingOrMovingANode() {
        let shares = [Stats.AccessPointShare(name: "Living Room AP", pointPercent: 92),
                      Stats.AccessPointShare(name: "access point ending :2F", pointPercent: 8)]

        let advice = HeatmapAdvisorBuilder.advice(for: Self.stats(weakRows: 0 ..< 3, weakCols: 4 ..< 10, accessPoints: shares))

        #expect(Array(advice.request.facts.suffix(3)) == [
            "Access points: 2",
            "Living Room AP: connected at 92% of points",
            "access point ending :2F: connected at 8% of points"
        ])
        #expect(advice.keyPoints == [
            "The north-east corner is weak (18% of the area, worst -84 dBm).",
            "Living Room AP was the connected access point at 92% of points.",
            "Add a mesh node or move one toward the north-east corner."
        ])
        #expect(advice.action == .addOrMoveNode(toward: "the north-east corner"))
    }

    @Test func aSingleAccessPointIsNotADominanceKeyPoint() {
        let advice = HeatmapAdvisorBuilder.advice(
            for: Self.stats(weakRows: 0 ..< 3, weakCols: 4 ..< 10, accessPoints: [.init(name: "Router", pointPercent: 100)])
        )

        #expect(Array(advice.request.facts.suffix(2)) == ["Access points: 1", "Router: connected at 100% of points"])
        #expect(!advice.keyPoints.contains { $0.contains("connected access point") })
        #expect(advice.action == .moveAccessPoint(toward: "the north-east corner"))
    }

    @Test func twoWeakRegionsInOnePlaceAreOneKeyPoint() {
        // Columns 7 and 9 of the top three rows: two regions, both in the north-east corner.
        var grid: [[Double?]] = Array(repeating: Array(repeating: -50, count: 10), count: 10)
        for row in 0 ..< 3 {
            grid[row][7] = -80
            grid[row][9] = -82
        }

        let stats = Stats(grid: grid, pointCount: 24)
        let advice = HeatmapAdvisorBuilder.advice(for: stats)

        #expect(stats.weakRegions.map(\.location) == [.compass(.northEast), .compass(.northEast)])
        #expect(advice.keyPoints == [
            "The north-east corner is weak (3% of the area, worst -80 dBm).",
            "Try moving the access point toward the north-east corner."
        ])
        #expect(advice.request.facts.contains("Weak areas: 2"))
        #expect(advice.request.facts.contains("Weak places: the north-east corner"))
    }

    @Test func theWeakAreaCountIsNotCappedAtTheListedThree() {
        // Four separate weak patches: 4 cells north-west, 6 south-east, 2 at the east edge, 1 in the centre.
        var grid: [[Double?]] = Array(repeating: Array(repeating: -50, count: 10), count: 10)
        for (row, col) in [(0, 0), (0, 1), (1, 0), (1, 1)] { grid[row][col] = -80 }
        for (row, col) in [(8, 7), (8, 8), (8, 9), (9, 7), (9, 8), (9, 9)] { grid[row][col] = -90 }
        for (row, col) in [(4, 9), (5, 9)] { grid[row][col] = -78 }
        grid[5][4] = -76

        let advice = HeatmapAdvisorBuilder.advice(for: Stats(grid: grid, pointCount: 24))

        #expect(advice.request.facts.contains("Weak areas: 4"))
        #expect(advice.request.facts.contains("Weak places: the south-east corner, the north-west corner, the east side"))
    }

    // MARK: - Sparse surveys

    @Test func fewerThanTenSpotsGetAHintInsteadOfAdvice() {
        let points = (0 ..< 9).map { MeasurementPoint(floorPlanX: Double($0) / 9, floorPlanY: 0.5, rssi: -60) }

        let advice = HeatmapAdvisorBuilder.advice(points: points, floorPlan: Self.plan)

        #expect(HeatmapAdvisorBuilder.minimumPoints == 10)
        #expect(advice == .sparse(hint: "Survey at least 10 different spots with a Wi-Fi signal reading to get advice. This survey has 9."))
    }

    @Test func noPlanGetsAHintInsteadOfAdvice() {
        let points = (0 ..< 12).map { MeasurementPoint(floorPlanX: Double($0) / 12, floorPlanY: 0.5, rssi: -60) }

        #expect(HeatmapAdvisorBuilder.advice(points: points, floorPlan: nil)
            == .sparse(hint: "Load a floor plan and survey at least 10 different spots with a Wi-Fi signal reading to get advice."))
    }

    @Test func pointsWithoutASignalReadingAreLeftOut() {
        // Both apps record -100 dBm when there is no reading (no Shortcut, not associated).
        let readings = (0 ..< 10).map { MeasurementPoint(floorPlanX: Double($0) / 9, floorPlanY: 0.5, rssi: -55) }
        let placeholders = (0 ..< 5).map { MeasurementPoint(floorPlanX: Double($0) / 4, floorPlanY: 0.1, rssi: -100, ssid: "Home") }

        guard case let .ready(advice) = HeatmapAdvisorBuilder.advice(points: readings + placeholders, floorPlan: Self.plan) else {
            Issue.record("expected advice")
            return
        }
        #expect(HeatmapAdvisorBuilder.noReadingRSSI == -100)
        #expect(advice.request.facts.first == "Measured points: 10")
        #expect(advice.request.facts.contains("Area with weak signal (below -75 dBm): 0%"))
    }

    @Test func pointsFlaggedWithoutAReadingAreLeftOut() {
        // Captured since the flag existed: rssiUnavailable says the -60 is not a reading.
        let readings = (0 ..< 6).map { MeasurementPoint(floorPlanX: Double($0) / 5, floorPlanY: 0.5, rssi: -55) }
        let flagged = (0 ..< 6).map { MeasurementPoint(floorPlanX: Double($0) / 5, floorPlanY: 0.1, rssi: -60, rssiUnavailable: true) }

        #expect(HeatmapAdvisorBuilder.advice(points: readings + flagged, floorPlan: Self.plan)
            == .sparse(hint: "Survey at least 10 different spots with a Wi-Fi signal reading to get advice. This survey has 6."))
    }

    @Test func tooFewReadingsGetTheHint() {
        let readings = (0 ..< 4).map { MeasurementPoint(floorPlanX: Double($0) / 4, floorPlanY: 0.5, rssi: -55) }
        let placeholders = (0 ..< 8).map { MeasurementPoint(floorPlanX: Double($0) / 8, floorPlanY: 0.1, rssi: -100) }

        #expect(HeatmapAdvisorBuilder.advice(points: readings + placeholders, floorPlan: Self.plan)
            == .sparse(hint: "Survey at least 10 different spots with a Wi-Fi signal reading to get advice. This survey has 4."))
    }

    @Test func aSpotMeasuredManyTimesCountsOnce() {
        // Continuous capture with the cursor still: 10 readings at one spot, 5 elsewhere.
        let still = (0 ..< 10).map { _ in MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -55) }
        let moved = (0 ..< 5).map { MeasurementPoint(floorPlanX: Double($0) / 4, floorPlanY: 0.1, rssi: -55) }

        #expect(HeatmapAdvisorBuilder.advice(points: still + moved, floorPlan: Self.plan)
            == .sparse(hint: "Survey at least 10 different spots with a Wi-Fi signal reading to get advice. This survey has 6."))
    }

    @Test func spotsOffThePlanHaveNothingToJudge() {
        // Ten readings, all far outside the plan's 0…1 square: no grid cell is within reach.
        let points = (0 ..< 10).map { MeasurementPoint(floorPlanX: 3 + Double($0), floorPlanY: 3, rssi: -55) }

        #expect(HeatmapAdvisorBuilder.advice(points: points, floorPlan: Self.plan)
            == .sparse(hint: "None of the measured spots is on the plan, so there is nothing to judge yet."))
    }

    @Test func tenSpotsOnAPlanGetAdvice() {
        let points = (0 ..< 10).map { MeasurementPoint(floorPlanX: Double($0) / 9, floorPlanY: 0.5, rssi: -60) }

        guard case let .ready(advice) = HeatmapAdvisorBuilder.advice(points: points, floorPlan: Self.plan) else {
            Issue.record("expected advice")
            return
        }
        #expect(advice.request.facts.first == "Measured points: 10")
    }
}
