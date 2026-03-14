import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Test Helpers

private func makeFloorPlan(
    imageData: Data = Data([0x89, 0x50, 0x4E, 0x47]),
    widthMeters: Double = 20.0,
    heightMeters: Double = 15.0,
    pixelWidth: Int = 800,
    pixelHeight: Int = 600
) -> FloorPlan {
    FloorPlan(
        imageData: imageData,
        widthMeters: widthMeters,
        heightMeters: heightMeters,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight
    )
}

private func makeSurveyProject(
    name: String = "Test Survey",
    points: [MeasurementPoint] = []
) -> SurveyProject {
    SurveyProject(
        name: name,
        floorPlan: makeFloorPlan(),
        measurementPoints: points
    )
}

// MARK: - SurveyProject Tests

struct SurveyProjectTests {

    @Test("init with defaults produces valid project")
    func initWithDefaults() {
        let project = makeSurveyProject()
        #expect(project.name == "Test Survey")
        #expect(project.measurementPoints.isEmpty)
        #expect(project.surveyMode == .blueprint)
        #expect(project.metadata.buildingName == nil)
    }

    @Test("averageRSSI returns nil for empty points")
    func averageRSSIEmpty() {
        let project = makeSurveyProject()
        #expect(project.averageRSSI == nil)
    }

    @Test("averageRSSI computes correctly")
    func averageRSSIComputed() {
        let points = [
            MeasurementPoint(rssi: -40),
            MeasurementPoint(rssi: -60),
            MeasurementPoint(rssi: -80),
        ]
        let project = makeSurveyProject(points: points)
        #expect(project.averageRSSI == -60)
    }

    @Test("minRSSI returns weakest signal")
    func minRSSI() {
        let points = [
            MeasurementPoint(rssi: -40),
            MeasurementPoint(rssi: -85),
            MeasurementPoint(rssi: -60),
        ]
        let project = makeSurveyProject(points: points)
        #expect(project.minRSSI == -85)
    }

    @Test("maxRSSI returns strongest signal")
    func maxRSSI() {
        let points = [
            MeasurementPoint(rssi: -40),
            MeasurementPoint(rssi: -85),
            MeasurementPoint(rssi: -60),
        ]
        let project = makeSurveyProject(points: points)
        #expect(project.maxRSSI == -40)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let metadata = SurveyMetadata(buildingName: "HQ", floorNumber: "2", notes: "Main office")
        let floorPlan = makeFloorPlan()
        let points = [
            MeasurementPoint(
                floorPlanX: 0.5, floorPlanY: 0.3,
                rssi: -48, noiseFloor: -90, snr: 42,
                ssid: "Corp", bssid: "AA:BB:CC:DD:EE:FF",
                channel: 36, frequency: 5180, band: .band5GHz,
                linkSpeed: 866, downloadSpeed: 120.0, uploadSpeed: 45.0,
                latency: 8.5, connectedAPName: "AP-1"
            ),
        ]
        let original = SurveyProject(
            name: "Office Survey",
            floorPlan: floorPlan,
            measurementPoints: points,
            surveyMode: .arAssisted,
            metadata: metadata
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SurveyProject.self, from: encoded)

        #expect(decoded.id == original.id)
        #expect(decoded.name == "Office Survey")
        #expect(decoded.surveyMode == .arAssisted)
        #expect(decoded.metadata.buildingName == "HQ")
        #expect(decoded.metadata.floorNumber == "2")
        #expect(decoded.metadata.notes == "Main office")
        #expect(decoded.measurementPoints.count == 1)

        let point = decoded.measurementPoints[0]
        #expect(point.rssi == -48)
        #expect(point.noiseFloor == -90)
        #expect(point.snr == 42)
        #expect(point.ssid == "Corp")
        #expect(point.bssid == "AA:BB:CC:DD:EE:FF")
        #expect(point.channel == 36)
        #expect(point.frequency == 5180)
        #expect(point.band == .band5GHz)
        #expect(point.linkSpeed == 866)
        #expect(point.downloadSpeed == 120.0)
        #expect(point.uploadSpeed == 45.0)
        #expect(point.latency == 8.5)
        #expect(point.connectedAPName == "AP-1")
    }

    @Test("Codable round-trip preserves floor plan fields")
    func floorPlanCodableRoundTrip() throws {
        let calibrationPoints = [
            CalibrationPoint(pixelX: 100, pixelY: 200, realWorldX: 0, realWorldY: 0),
            CalibrationPoint(pixelX: 500, pixelY: 200, realWorldX: 10, realWorldY: 0),
        ]
        let walls = [
            WallSegment(startX: 0, startY: 0, endX: 20, endY: 0),
        ]
        let floorPlan = FloorPlan(
            imageData: Data([1, 2, 3]),
            widthMeters: 25.0,
            heightMeters: 18.0,
            pixelWidth: 1000,
            pixelHeight: 720,
            origin: .arGenerated,
            calibrationPoints: calibrationPoints,
            walls: walls
        )

        let encoded = try JSONEncoder().encode(floorPlan)
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: encoded)

        #expect(decoded.id == floorPlan.id)
        #expect(decoded.imageData == Data([1, 2, 3]))
        #expect(decoded.widthMeters == 25.0)
        #expect(decoded.heightMeters == 18.0)
        #expect(decoded.pixelWidth == 1000)
        #expect(decoded.pixelHeight == 720)
        #expect(decoded.origin == .arGenerated)
        #expect(decoded.calibrationPoints?.count == 2)
        #expect(decoded.walls?.count == 1)
    }
}

// MARK: - FloorPlan Tests

struct FloorPlanTests {

    @Test("metersPerPixelX calculated correctly")
    func metersPerPixelX() {
        let plan = FloorPlan(
            imageData: Data(),
            widthMeters: 20.0,
            heightMeters: 10.0,
            pixelWidth: 1000,
            pixelHeight: 500
        )
        #expect(plan.metersPerPixelX == 0.02)
    }

    @Test("metersPerPixelY calculated correctly")
    func metersPerPixelY() {
        let plan = FloorPlan(
            imageData: Data(),
            widthMeters: 20.0,
            heightMeters: 10.0,
            pixelWidth: 1000,
            pixelHeight: 500
        )
        #expect(plan.metersPerPixelY == 0.02)
    }

    @Test("metersPerPixel returns 0 for zero dimensions")
    func metersPerPixelZeroDimensions() {
        let plan = FloorPlan(
            imageData: Data(),
            widthMeters: 20.0,
            heightMeters: 10.0,
            pixelWidth: 0,
            pixelHeight: 0
        )
        #expect(plan.metersPerPixelX == 0)
        #expect(plan.metersPerPixelY == 0)
    }
}

// MARK: - CalibrationPoint Tests

struct CalibrationPointTests {

    @Test("metersPerPixel calculates correctly")
    func metersPerPixel() {
        let pointA = CalibrationPoint(pixelX: 0, pixelY: 0)
        let pointB = CalibrationPoint(pixelX: 300, pixelY: 400)
        let result = CalibrationPoint.metersPerPixel(pointA: pointA, pointB: pointB, knownDistanceMeters: 10.0)
        #expect(abs(result - 0.02) < 0.001, "500px distance, 10m => 0.02 m/px, got \(result)")
    }

    @Test("metersPerPixel returns 0 for coincident points")
    func metersPerPixelCoincident() {
        let pointA = CalibrationPoint(pixelX: 100, pixelY: 100)
        let pointB = CalibrationPoint(pixelX: 100, pixelY: 100)
        let result = CalibrationPoint.metersPerPixel(pointA: pointA, pointB: pointB, knownDistanceMeters: 5.0)
        #expect(result == 0)
    }
}

// MARK: - MeasurementPoint Tests

struct MeasurementPointTests {

    @Test("default init has expected values")
    func defaultInit() {
        let point = MeasurementPoint()
        #expect(point.rssi == -100)
        #expect(point.floorPlanX == 0)
        #expect(point.floorPlanY == 0)
        #expect(point.ssid == nil)
        #expect(point.downloadSpeed == nil)
    }

    @Test("Identifiable with unique IDs")
    func uniqueIDs() {
        let point1 = MeasurementPoint(rssi: -50)
        let point2 = MeasurementPoint(rssi: -50)
        #expect(point1.id != point2.id)
    }

    @Test("Equatable compares all fields")
    func equatable() {
        let id = UUID()
        let date = Date()
        let point1 = MeasurementPoint(id: id, timestamp: date, rssi: -50, ssid: "Net")
        let point2 = MeasurementPoint(id: id, timestamp: date, rssi: -50, ssid: "Net")
        #expect(point1 == point2)
    }
}

// MARK: - SurveyMetadata Tests

struct SurveyMetadataTests {

    @Test("default init has nil fields")
    func defaultInit() {
        let meta = SurveyMetadata()
        #expect(meta.buildingName == nil)
        #expect(meta.floorNumber == nil)
        #expect(meta.notes == nil)
    }

    @Test("Equatable")
    func equatable() {
        let meta1 = SurveyMetadata(buildingName: "HQ", floorNumber: "3")
        let meta2 = SurveyMetadata(buildingName: "HQ", floorNumber: "3")
        #expect(meta1 == meta2)
    }
}

// MARK: - SurveyMode Tests

struct SurveyModeTests {

    @Test("all cases exist")
    func allCases() {
        let cases = SurveyMode.allCases
        #expect(cases.contains(.blueprint))
        #expect(cases.contains(.arAssisted))
        #expect(cases.contains(.arContinuous))
        #expect(cases.count == 3)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for mode in SurveyMode.allCases {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(SurveyMode.self, from: encoded)
            #expect(decoded == mode)
        }
    }
}

// MARK: - HeatmapVisualization Tests

struct HeatmapVisualizationTests {

    @Test("all cases exist")
    func allCases() {
        // Current model has 7 visualization types
        #expect(HeatmapVisualization.allCases.count == 7)
    }

    @Test("displayName is non-empty for all cases")
    func displayNames() {
        for vis in HeatmapVisualization.allCases {
            #expect(!vis.displayName.isEmpty)
        }
    }

    @Test("isHigherBetter is false for latency")
    func latencyIsLowerBetter() {
        #expect(!HeatmapVisualization.latency.isHigherBetter)
    }

    @Test("isHigherBetter is true for signalStrength")
    func signalStrengthIsHigherBetter() {
        #expect(HeatmapVisualization.signalStrength.isHigherBetter)
    }

    @Test("isHigherBetter is false for noiseFloor")
    func noiseFloorIsLowerBetter() {
        #expect(!HeatmapVisualization.noiseFloor.isHigherBetter)
    }

    @Test("isHigherBetter is true for frequencyBand")
    func frequencyBandIsHigherBetter() {
        #expect(HeatmapVisualization.frequencyBand.isHigherBetter)
    }

    // MARK: - requiresActiveScan

    @Test("requiresActiveScan is false for signalStrength")
    func signalStrengthIsPassive() {
        #expect(HeatmapVisualization.signalStrength.requiresActiveScan == false)
    }

    @Test("requiresActiveScan is false for signalToNoise")
    func signalToNoiseIsPassive() {
        #expect(HeatmapVisualization.signalToNoise.requiresActiveScan == false)
    }

    @Test("requiresActiveScan is false for noiseFloor")
    func noiseFloorIsPassive() {
        #expect(HeatmapVisualization.noiseFloor.requiresActiveScan == false)
    }

    @Test("requiresActiveScan is false for frequencyBand")
    func frequencyBandIsPassive() {
        #expect(HeatmapVisualization.frequencyBand.requiresActiveScan == false)
    }

    @Test("requiresActiveScan is true for downloadSpeed")
    func downloadSpeedRequiresActiveScan() {
        #expect(HeatmapVisualization.downloadSpeed.requiresActiveScan == true)
    }

    @Test("requiresActiveScan is true for uploadSpeed")
    func uploadSpeedRequiresActiveScan() {
        #expect(HeatmapVisualization.uploadSpeed.requiresActiveScan == true)
    }

    @Test("requiresActiveScan is true for latency")
    func latencyRequiresActiveScan() {
        #expect(HeatmapVisualization.latency.requiresActiveScan == true)
    }

    // MARK: - unit

    @Test("unit for signalStrength is dBm")
    func signalStrengthUnitIsDBm() {
        #expect(HeatmapVisualization.signalStrength.unit == "dBm")
    }

    @Test("unit for signalToNoise is dB")
    func signalToNoiseUnitIsDB() {
        #expect(HeatmapVisualization.signalToNoise.unit == "dB")
    }

    @Test("unit for noiseFloor is dBm")
    func noiseFloorUnitIsDBm() {
        #expect(HeatmapVisualization.noiseFloor.unit == "dBm")
    }

    @Test("unit for downloadSpeed is Mbps")
    func downloadSpeedUnitIsMbps() {
        #expect(HeatmapVisualization.downloadSpeed.unit == "Mbps")
    }

    @Test("unit for uploadSpeed is Mbps")
    func uploadSpeedUnitIsMbps() {
        #expect(HeatmapVisualization.uploadSpeed.unit == "Mbps")
    }

    @Test("unit for latency is ms")
    func latencyUnitIsMs() {
        #expect(HeatmapVisualization.latency.unit == "ms")
    }

    @Test("unit for frequencyBand is GHz")
    func frequencyBandUnitIsGHz() {
        #expect(HeatmapVisualization.frequencyBand.unit == "GHz")
    }

    // MARK: - valueRange

    @Test("signalStrength valueRange is -100...0")
    func signalStrengthValueRange() {
        #expect(HeatmapVisualization.signalStrength.valueRange == -100.0...0.0)
    }

    @Test("latency valueRange is 0...200")
    func latencyValueRange() {
        #expect(HeatmapVisualization.latency.valueRange == 0.0...200.0)
    }

    @Test("downloadSpeed valueRange is 0...500")
    func downloadSpeedValueRange() {
        #expect(HeatmapVisualization.downloadSpeed.valueRange == 0.0...500.0)
    }

    // MARK: - extractValue

    @Test("noiseFloor extracts noiseFloor from point")
    func noiseFloorExtractsNoiseFloor() {
        let point = MeasurementPoint(rssi: -55, noiseFloor: -88)
        #expect(HeatmapVisualization.noiseFloor.extractValue(from: point) == -88)
    }

    @Test("noiseFloor returns nil when noiseFloor is nil")
    func noiseFloorReturnsNilWhenMissing() {
        let point = MeasurementPoint(rssi: -55)
        #expect(HeatmapVisualization.noiseFloor.extractValue(from: point) == nil)
    }

    @Test("frequencyBand returns 1.0 for 2.4 GHz")
    func frequencyBand2_4GHz() {
        let point = MeasurementPoint(rssi: -55, band: .band2_4GHz)
        #expect(HeatmapVisualization.frequencyBand.extractValue(from: point) == 1.0)
    }

    @Test("frequencyBand returns 2.0 for 5 GHz")
    func frequencyBand5GHz() {
        let point = MeasurementPoint(rssi: -55, band: .band5GHz)
        #expect(HeatmapVisualization.frequencyBand.extractValue(from: point) == 2.0)
    }

    @Test("frequencyBand returns 3.0 for 6 GHz")
    func frequencyBand6GHz() {
        let point = MeasurementPoint(rssi: -55, band: .band6GHz)
        #expect(HeatmapVisualization.frequencyBand.extractValue(from: point) == 3.0)
    }

    @Test("frequencyBand returns nil when band is nil")
    func frequencyBandNilWhenBandIsNil() {
        let point = MeasurementPoint(rssi: -55)
        #expect(HeatmapVisualization.frequencyBand.extractValue(from: point) == nil)
    }

    // MARK: - hasData

    @Test("hasData returns false for empty points array")
    func hasDataFalseForEmptyPoints() {
        #expect(HeatmapVisualization.signalStrength.hasData(in: []) == false)
    }

    @Test("hasData returns true when at least one point has the value")
    func hasDataTrueWhenOnePointHasValue() {
        let points = [
            MeasurementPoint(rssi: -50),
            MeasurementPoint(rssi: -60, downloadSpeed: 100.0),
        ]
        #expect(HeatmapVisualization.downloadSpeed.hasData(in: points) == true)
    }

    @Test("hasData returns false when no points have the value")
    func hasDataFalseWhenNoPointsHaveValue() {
        let points = [
            MeasurementPoint(rssi: -50),
            MeasurementPoint(rssi: -60),
        ]
        #expect(HeatmapVisualization.downloadSpeed.hasData(in: points) == false)
    }

    @Test("hasData for signalStrength is always true when points exist")
    func hasDataSignalStrengthAlwaysTrue() {
        let points = [MeasurementPoint(rssi: -75)]
        #expect(HeatmapVisualization.signalStrength.hasData(in: points) == true)
    }

    @Test("hasData for noiseFloor is false when no point has noiseFloor")
    func hasDataNoiseFloorFalseWithoutData() {
        let points = [MeasurementPoint(rssi: -55)]
        #expect(HeatmapVisualization.noiseFloor.hasData(in: points) == false)
    }

    @Test("hasData for frequencyBand is true when band is populated")
    func hasDataFrequencyBandTrueWithBand() {
        let points = [MeasurementPoint(rssi: -55, band: .band5GHz)]
        #expect(HeatmapVisualization.frequencyBand.hasData(in: points) == true)
    }
}

// MARK: - FloorPlanOrigin Tests

struct FloorPlanOriginTests {

    @Test("all cases exist")
    func allCases() {
        let origins: [FloorPlanOrigin] = [.imported, .arGenerated, .drawn]
        #expect(origins.count == 3)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let origins: [FloorPlanOrigin] = [.imported, .arGenerated, .drawn]
        for origin in origins {
            let encoded = try JSONEncoder().encode(origin)
            let decoded = try JSONDecoder().decode(FloorPlanOrigin.self, from: encoded)
            #expect(decoded == origin)
        }
    }
}
