import Testing
import Foundation
@testable import NetMonitorCore

/// What the heatmap advisor knows about a finished survey (#455), computed by the app.
@Suite("HeatmapSurveyStatistics")
struct HeatmapSurveyStatisticsTests {
    /// A 10 × 10 grid at `base` dBm, with `value` in the rows and columns given. Row 0 is north.
    static func grid(_ base: Double = -50, _ value: Double = -85, rows: Range<Int> = 0 ..< 0, cols: Range<Int> = 0 ..< 0) -> [[Double?]] {
        (0 ..< 10).map { row in
            (0 ..< 10).map { col in rows.contains(row) && cols.contains(col) ? value : base }
        }
    }

    @Test func aWeakNorthEastCornerIsItsOwnRegion() {
        // 3 × 3 weak cells in the top-right corner: 9% of 100 cells.
        let stats = HeatmapSurveyStatistics(grid: Self.grid(rows: 0 ..< 3, cols: 7 ..< 10), pointCount: 12)

        #expect(stats.coverage == HeatmapSurveyStatistics.Coverage(good: 91, fair: 0, weak: 9))
        #expect(stats.weakRegions.count == 1)
        let region = stats.weakRegions[0]
        #expect(region.areaPercent == 9)
        #expect(region.worstRSSI == -85)
        #expect(region.meanRSSI == -85)
        #expect(region.location == .compass(.northEast))
        #expect(region.location.phrase == "the north-east corner")
    }

    @Test func thresholdsCountTheirBoundaryAsTheBetterBand() {
        // -67 is good and -75 is fair; just below each falls to the next band.
        let grid: [[Double?]] = [[-67, -67.5, -75, -75.5]]

        let stats = HeatmapSurveyStatistics(grid: grid, pointCount: 12)

        #expect(stats.coverage == HeatmapSurveyStatistics.Coverage(good: 25, fair: 50, weak: 25))
        #expect(HeatmapSurveyStatistics.goodRSSI == -67)
        #expect(HeatmapSurveyStatistics.fairRSSI == -75)
    }

    @Test func cellsOutsideTheSurveyedAreaDoNotCount() {
        // Half the grid unsurveyed; of the surveyed half, one cell in five is weak.
        let grid: [[Double?]] = [[-50, -50, -50, -50, -85], [nil, nil, nil, nil, nil]]

        let stats = HeatmapSurveyStatistics(grid: grid, pointCount: 12)

        #expect(stats.coverage == HeatmapSurveyStatistics.Coverage(good: 80, fair: 0, weak: 20))
        #expect(stats.weakRegions.map(\.areaPercent) == [20])
    }

    @Test func aLabelledRoomNamesTheRegionInsteadOfTheCompass() {
        let rooms = [
            RoomLabel(text: "Kitchen", normalizedX: 0.85, normalizedY: 0.15),
            RoomLabel(text: "Lounge", normalizedX: 0.2, normalizedY: 0.8)
        ]

        let stats = HeatmapSurveyStatistics(grid: Self.grid(rows: 0 ..< 3, cols: 7 ..< 10), pointCount: 12, roomLabels: rooms)

        #expect(stats.weakRegions.map(\.location) == [.room("Kitchen")])
        #expect(stats.weakRegions[0].location.phrase == "the Kitchen")
    }

    @Test func regionsAreLargestFirstAndAtMostThree() {
        // Four separate weak patches: 4 cells north-west, 6 south-east, 2 at the east edge, 1 in the centre.
        var grid = Self.grid()
        for (row, col) in [(0, 0), (0, 1), (1, 0), (1, 1)] { grid[row][col] = -80 }
        for (row, col) in [(8, 7), (8, 8), (8, 9), (9, 7), (9, 8), (9, 9)] { grid[row][col] = -90 }
        for (row, col) in [(4, 9), (5, 9)] { grid[row][col] = -78 }
        grid[5][4] = -76

        let stats = HeatmapSurveyStatistics(grid: grid, pointCount: 12)

        #expect(stats.weakRegions.map(\.areaPercent) == [6, 4, 2])
        #expect(stats.weakRegions.map(\.location) == [.compass(.southEast), .compass(.northWest), .compass(.east)])
        #expect(stats.weakRegions.map(\.worstRSSI) == [-90, -80, -78])
        #expect(stats.weakRegionCount == 4)
        #expect(stats.coverage.weak == 13)
    }

    @Test func cellsTouchingAtACornerAreOneRegion() {
        // A diagonal staircase of weak cells, as an interpolated contour has.
        var grid = Self.grid()
        for step in 0 ..< 4 { grid[step][9 - step] = -85 }

        let stats = HeatmapSurveyStatistics(grid: grid, pointCount: 12)

        #expect(stats.weakRegions.map(\.areaPercent) == [4])
    }

    @Test func aRegionUnderHalfAPercentIsNotReported() {
        // One weak cell in 300: it rounds to 0% of the area.
        var row: [Double?] = Array(repeating: -50, count: 300)
        row[150] = -90

        #expect(HeatmapSurveyStatistics(grid: [row], pointCount: 12).weakRegions.isEmpty)
    }

    @Test func compassPositionsSplitThePlanInThirds() {
        #expect(HeatmapSurveyStatistics.Compass(x: 0.1, y: 0.1) == .northWest)
        #expect(HeatmapSurveyStatistics.Compass(x: 0.5, y: 0.5) == .centre)
        #expect(HeatmapSurveyStatistics.Compass(x: 1, y: 0.5) == .east)
        #expect(HeatmapSurveyStatistics.Compass(x: 0.5, y: 1) == .south)
        #expect(HeatmapSurveyStatistics.Compass.north.place == "the north side")
        #expect(HeatmapSurveyStatistics.Compass.centre.place == "the centre")
        #expect(HeatmapSurveyStatistics.Compass.southWest.place == "the south-west corner")
    }

    @Test func signalFallsOffFromTheStrongestCellTowardTheWeakest() {
        var grid = Self.grid(-60)
        grid[9][0] = -40
        grid[0][9] = -88

        let stats = HeatmapSurveyStatistics(grid: grid, pointCount: 12)

        #expect(stats.falloff == .northEast)
    }

    @Test func weakSidesAroundAStrongMiddleHaveNoFalloff() {
        // Both outer columns weak, the middle strong: the two centroids coincide.
        let grid: [[Double?]] = (0 ..< 10).map { _ in (0 ..< 10).map { col in col == 0 || col == 9 ? -82 : -55 } }

        #expect(HeatmapSurveyStatistics(grid: grid, pointCount: 12).falloff == nil)
    }

    @Test func extremesWithinACellHaveNoFalloff() {
        var grid = Self.grid(-60)
        grid[4][4] = -40
        grid[5][5] = -88

        #expect(HeatmapSurveyStatistics(grid: grid, pointCount: 12).falloff == nil)
    }

    @Test func falloffIsMeasuredOnThePlansAxes() {
        // 10 rows × 40 columns: from the bottom-left cell to the cell 9 columns and 9 rows away.
        // 9 of 39 columns is a quarter of the width, 9 of 9 rows is the full height: north.
        var grid: [[Double?]] = Array(repeating: Array(repeating: -60, count: 40), count: 10)
        grid[9][0] = -40
        grid[0][9] = -88

        #expect(HeatmapSurveyStatistics(grid: grid, pointCount: 12).falloff == .north)
    }

    @Test func roomsAreNearestInMetresOnARectangularPlan() {
        // A 20 m × 5 m plan; weak cells top-middle at (0.5, 0). The Hall label is 4 m away (0.8 of
        // the 5 m height); the Study label is 0.22 of the width away, which is 4.4 m.
        var grid = Self.grid()
        grid[0][4] = -85
        grid[0][5] = -85
        let rooms = [RoomLabel(text: "Hall", normalizedX: 0.5, normalizedY: 0.8),
                     RoomLabel(text: "Study", normalizedX: 0.72, normalizedY: 0)]

        let stats = HeatmapSurveyStatistics(grid: grid, pointCount: 12, roomLabels: rooms, planWidth: 20, planHeight: 5)

        #expect(stats.weakRegions.map(\.location) == [.room("Hall")])
    }

    @Test func aGridWithNoSurveyedCellIsEmpty() {
        let stats = HeatmapSurveyStatistics(grid: [[nil, nil], [nil, nil]], pointCount: 12)

        #expect(stats.surveyedCells == 0)
        #expect(stats.coverage == HeatmapSurveyStatistics.Coverage(good: 0, fair: 0, weak: 0))
        #expect(stats.weakRegions.isEmpty)
        #expect(stats.falloff == nil)
    }

    @Test func anEvenGridHasNoFalloff() {
        #expect(HeatmapSurveyStatistics(grid: Self.grid(), pointCount: 12).falloff == nil)
    }

    @Test func accessPointSharesNameKnownDevicesAndFallBackToTheLastOctet() {
        let points = [
            MeasurementPoint(bssid: "AA:BB:CC:DD:EE:01"),
            MeasurementPoint(bssid: "aa:bb:cc:dd:ee:1"),
            MeasurementPoint(bssid: "aa-bb-cc-dd-ee-01"),
            MeasurementPoint(bssid: "AA:BB:CC:DD:EE:2"),
            MeasurementPoint(bssid: nil)
        ]

        let shares = HeatmapSurveyStatistics.accessPointShares(points, names: ["AA:BB:CC:DD:EE:01": "Living Room AP"])

        #expect(shares == [
            HeatmapSurveyStatistics.AccessPointShare(name: "Living Room AP", pointPercent: 75),
            HeatmapSurveyStatistics.AccessPointShare(name: "access point ending :02", pointPercent: 25)
        ])
    }

    @Test func pointsWithoutABSSIDHaveNoAccessPointShares() {
        #expect(HeatmapSurveyStatistics.accessPointShares([MeasurementPoint(), MeasurementPoint()], names: [:]).isEmpty)
    }

    @Test func accessPointNamesComeFromTheDevicesDisplayName() {
        let devices = [
            LocalDevice(ipAddress: "192.168.1.2", macAddress: "aa:bb:cc:dd:ee:1", customName: "Hall Mesh"),
            LocalDevice(ipAddress: "192.168.1.3", macAddress: "")
        ]

        #expect(HeatmapSurveyStatistics.accessPointNames(devices) == ["AA:BB:CC:DD:EE:01": "Hall Mesh"])
    }

    @Test func pointsAreInterpolatedOnlyWithinTheRenderersReach() {
        // Strong along the west, weak in the north-east corner; nothing measured in the south-east.
        var points: [MeasurementPoint] = []
        for y in stride(from: 0.0, through: 1.0, by: 0.25) {
            points.append(MeasurementPoint(floorPlanX: 0, floorPlanY: y, rssi: -45))
            points.append(MeasurementPoint(floorPlanX: 0.25, floorPlanY: y, rssi: -55))
        }
        points.append(MeasurementPoint(floorPlanX: 1, floorPlanY: 0, rssi: -88))
        points.append(MeasurementPoint(floorPlanX: 0.9, floorPlanY: 0.1, rssi: -84))

        let stats = HeatmapSurveyStatistics(points: points, configuration: .init(gridWidth: 40, gridHeight: 40))

        #expect(stats.pointCount == 12)
        #expect(stats.weakRegions.first?.location == .compass(.northEast))
        #expect(stats.weakRegions.first?.worstRSSI == -88)
        #expect(stats.coverage.good + stats.coverage.fair + stats.coverage.weak >= 99)
        #expect(stats.falloff == .east || stats.falloff == .northEast)
    }
}

/// Room labels travel from a RoomPlan blueprint onto the survey's floor plan (#455).
@Suite("FloorPlan room labels")
@MainActor
struct FloorPlanRoomLabelTests {
    static let kitchen = RoomLabel(text: "Kitchen", normalizedX: 0.8, normalizedY: 0.2)

    @Test func aBlueprintFloorKeepsItsRoomLabels() {
        let floor = BlueprintFloor(label: "Ground", floorNumber: 0, svgData: Data(), widthMeters: 10, heightMeters: 8,
                                   roomLabels: [Self.kitchen], wallSegments: [])

        #expect(BlueprintSaveLoadManager.floorPlanFromBlueprint(floor, renderWidth: 64).roomLabels == [Self.kitchen])
    }

    @Test func calibratingKeepsTheRoomLabels() {
        let state = HeatmapSurveyState()
        let plan = FloorPlan(imageData: Data(), widthMeters: 10, heightMeters: 8, pixelWidth: 100, pixelHeight: 80,
                             roomLabels: [Self.kitchen])
        state.setProject(SurveyProject(name: "Home", floorPlan: plan))
        state.addCalibrationPoint(at: .zero)
        state.addCalibrationPoint(at: CGPoint(x: 10, y: 0))

        state.completeCalibration(withDistance: 5)

        #expect(state.surveyProject?.floorPlan.roomLabels == [Self.kitchen])
    }

    @Test func aPlanSavedBeforeRoomLabelsStillDecodes() throws {
        let json = #"{"id":"\#(UUID())","imageData":"","widthMeters":10,"heightMeters":8,"pixelWidth":100,"pixelHeight":80,"origin":"imported"}"#

        let plan = try JSONDecoder().decode(FloorPlan.self, from: Data(json.utf8))

        #expect(plan.roomLabels == nil)
    }
}
