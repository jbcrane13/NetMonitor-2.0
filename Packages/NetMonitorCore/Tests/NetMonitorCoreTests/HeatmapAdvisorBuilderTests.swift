import Testing
import Foundation
@testable import NetMonitorCore

/// The summary request behind the heatmap advisor (#455): the app's statistics as facts and its
/// judgements, including the suggested action, as key points.
@Suite("HeatmapAdvisorBuilder")
struct HeatmapAdvisorBuilderTests {
    typealias Stats = HeatmapSurveyStatistics

    static let plan = FloorPlan(imageData: Data(), widthMeters: 10, heightMeters: 8, pixelWidth: 100, pixelHeight: 80)

    /// A 10 × 10 grid at -50 dBm with weak cells (-84 at the corner cell, -79 elsewhere) in the
    /// given rows and columns.
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
        let request = HeatmapAdvisorBuilder.request(Self.stats(weakRows: 0 ..< 3, weakCols: 4 ..< 10))

        #expect(request.kind == .summary)
        #expect(request.subject == "Wi-Fi heatmap survey")
        #expect(request.facts == [
            "Measured points: 24",
            "Area with good signal (-67 dBm or better): 82%",
            "Area with fair signal (-75 to -67 dBm): 0%",
            "Area with weak signal (below -75 dBm): 18%",
            "Weak areas: 1",
            "Weak area 1: the north-east corner, 18% of the area, worst -84 dBm, average -79 dBm",
            "Signal falls off toward the north-east"
        ])
        #expect(request.observations == [
            "The north-east corner is weak (18% of the area, worst -84 dBm).",
            "Try moving the access point toward the north-east corner."
        ])
    }

    @Test func aLargeWeakRegionSuggestsAddingANode() {
        // 30 of 100 cells.
        let request = HeatmapAdvisorBuilder.request(Self.stats(weakRows: 0 ..< 3, weakCols: 0 ..< 10))

        #expect(request.observations.last == "Add an access point or mesh node near the north side.")
    }

    @Test func aWeakRegionAtTheThresholdSuggestsAddingANode() {
        // 25 of 100 cells: 5 × 5 in the north-west.
        let request = HeatmapAdvisorBuilder.request(Self.stats(weakRows: 0 ..< 5, weakCols: 0 ..< 5))

        #expect(HeatmapAdvisorBuilder.addNodeRegionPercent == 25)
        #expect(request.observations.last == "Add an access point or mesh node near the north-west corner.")
    }

    @Test func littleWeakAreaNeedsNoChange() {
        // 4 of 100 cells: under the 5% that needs a change.
        let request = HeatmapAdvisorBuilder.request(Self.stats(weakRows: 0 ..< 2, weakCols: 8 ..< 10))

        #expect(HeatmapAdvisorBuilder.negligibleWeakPercent == 5)
        #expect(request.observations == ["Little of the surveyed area is weak, so no change is needed."])
    }

    @Test func aMostlyFairSurveyIsNotCalledGood() {
        // Every cell at -70 dBm: fair, nothing weak.
        let grid: [[Double?]] = Array(repeating: Array(repeating: -70, count: 10), count: 10)

        let request = HeatmapAdvisorBuilder.request(Stats(grid: grid, pointCount: 24))

        #expect(request.observations == ["Little of the surveyed area is weak, so no change is needed."])
        #expect(request.facts.contains("Area with fair signal (-75 to -67 dBm): 100%"))
    }

    @Test func aRoomNameWritesTheKeyPoints() {
        let rooms = [RoomLabel(text: "Kitchen", normalizedX: 0.8, normalizedY: 0.1)]

        let request = HeatmapAdvisorBuilder.request(Self.stats(weakRows: 0 ..< 3, weakCols: 4 ..< 10, roomLabels: rooms))

        #expect(request.observations == [
            "The Kitchen is weak (18% of the area, worst -84 dBm).",
            "Try moving the access point toward the Kitchen."
        ])
    }

    @Test func accessPointsAreFactsAndADominantOneIsAKeyPoint() {
        let shares = [Stats.AccessPointShare(name: "Living Room AP", pointPercent: 92),
                      Stats.AccessPointShare(name: "access point ending :2F", pointPercent: 8)]

        let request = HeatmapAdvisorBuilder.request(Self.stats(weakRows: 0 ..< 3, weakCols: 4 ..< 10, accessPoints: shares))

        #expect(Array(request.facts.suffix(3)) == [
            "Access points: 2",
            "Living Room AP: strongest at 92% of points",
            "access point ending :2F: strongest at 8% of points"
        ])
        #expect(request.observations.contains("Living Room AP was the strongest access point at 92% of points."))
    }

    @Test func aSingleAccessPointIsNotADominanceKeyPoint() {
        let request = HeatmapAdvisorBuilder.request(
            Self.stats(weakRows: 0 ..< 3, weakCols: 4 ..< 10, accessPoints: [.init(name: "Router", pointPercent: 100)])
        )

        #expect(request.facts.contains("Access points: 1"))
        #expect(!request.observations.contains { $0.contains("strongest access point") })
    }

    @Test func twoWeakRegionsInOnePlaceAreOneKeyPoint() {
        // Columns 7 and 9 of the top three rows: two regions, both in the north-east corner.
        var grid: [[Double?]] = Array(repeating: Array(repeating: -50, count: 10), count: 10)
        for row in 0 ..< 3 {
            grid[row][7] = -80
            grid[row][9] = -82
        }

        let stats = Stats(grid: grid, pointCount: 24)
        let request = HeatmapAdvisorBuilder.request(stats)

        #expect(stats.weakRegions.map(\.location) == [.compass(.northEast), .compass(.northEast)])
        #expect(request.observations == [
            "The north-east corner is weak (3% of the area, worst -80 dBm).",
            "Try moving the access point toward the north-east corner."
        ])
    }

    // MARK: - Sparse surveys

    @Test func fewerThanTenPointsGetsAHintInsteadOfAdvice() {
        let points = (0 ..< 9).map { MeasurementPoint(floorPlanX: Double($0) / 9, floorPlanY: 0.5, rssi: -60) }

        let advice = HeatmapAdvisorBuilder.advice(points: points, floorPlan: Self.plan)

        #expect(HeatmapAdvisorBuilder.minimumPoints == 10)
        #expect(advice == .sparse(hint: "Survey at least 10 points with a Wi-Fi signal reading to get advice. This survey has 9."))
    }

    @Test func noPlanGetsAHintInsteadOfAdvice() {
        let points = (0 ..< 12).map { MeasurementPoint(floorPlanX: Double($0) / 12, floorPlanY: 0.5, rssi: -60) }

        #expect(HeatmapAdvisorBuilder.advice(points: points, floorPlan: nil)
            == .sparse(hint: "Load a floor plan and survey at least 10 points with a Wi-Fi signal reading to get advice."))
    }

    @Test func pointsWithoutASignalReadingAreLeftOut() {
        // Both apps record -100 dBm when there is no reading (no Shortcut, not associated).
        let readings = (0 ..< 10).map { MeasurementPoint(floorPlanX: Double($0) / 9, floorPlanY: 0.5, rssi: -55) }
        let placeholders = (0 ..< 5).map { MeasurementPoint(floorPlanX: Double($0) / 4, floorPlanY: 0.1, rssi: -100, ssid: "Home") }

        guard case let .ready(request) = HeatmapAdvisorBuilder.advice(points: readings + placeholders, floorPlan: Self.plan) else {
            Issue.record("expected advice")
            return
        }
        #expect(HeatmapAdvisorBuilder.noReadingRSSI == -100)
        #expect(request.facts.first == "Measured points: 10")
        #expect(request.facts.contains("Area with weak signal (below -75 dBm): 0%"))
    }

    @Test func tooFewReadingsGetTheHint() {
        let readings = (0 ..< 4).map { MeasurementPoint(floorPlanX: Double($0) / 4, floorPlanY: 0.5, rssi: -55) }
        let placeholders = (0 ..< 8).map { MeasurementPoint(floorPlanX: Double($0) / 8, floorPlanY: 0.1, rssi: -100) }

        #expect(HeatmapAdvisorBuilder.advice(points: readings + placeholders, floorPlan: Self.plan)
            == .sparse(hint: "Survey at least 10 points with a Wi-Fi signal reading to get advice. This survey has 4."))
    }

    @Test func tenPointsOnAPlanGetAdvice() {
        let points = (0 ..< 10).map { MeasurementPoint(floorPlanX: Double($0) / 9, floorPlanY: 0.5, rssi: -60) }

        guard case let .ready(request) = HeatmapAdvisorBuilder.advice(points: points, floorPlan: Self.plan) else {
            Issue.record("expected advice")
            return
        }
        #expect(request.facts.first == "Measured points: 10")
    }
}
