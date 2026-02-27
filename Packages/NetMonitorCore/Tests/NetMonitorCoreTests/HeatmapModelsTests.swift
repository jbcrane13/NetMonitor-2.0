import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - HeatmapDataPoint Tests (6E)

@Suite("HeatmapDataPoint")
struct HeatmapDataPointTests {

    // MARK: - Codable Round-Trip

    @Test("HeatmapDataPoint Codable round-trip preserves all properties")
    func codableRoundTrip() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let original = HeatmapDataPoint(
            x: 150.5,
            y: 300.75,
            signalStrength: -55,
            timestamp: timestamp
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HeatmapDataPoint.self, from: data)

        #expect(decoded.x == original.x)
        #expect(decoded.y == original.y)
        #expect(decoded.signalStrength == original.signalStrength)
        #expect(abs(decoded.timestamp.timeIntervalSince(original.timestamp)) < 0.001)
    }

    @Test("HeatmapDataPoint Codable round-trip with negative signal strength")
    func codableNegativeSignal() throws {
        let original = HeatmapDataPoint(
            x: 0,
            y: 0,
            signalStrength: -90,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HeatmapDataPoint.self, from: data)

        #expect(decoded.signalStrength == -90)
    }

    @Test("HeatmapDataPoint Codable round-trip with zero coordinates")
    func codableZeroCoordinates() throws {
        let original = HeatmapDataPoint(
            x: 0.0,
            y: 0.0,
            signalStrength: -50,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HeatmapDataPoint.self, from: data)

        #expect(decoded.x == 0.0)
        #expect(decoded.y == 0.0)
    }

    @Test("HeatmapDataPoint Codable round-trip with large coordinates")
    func codableLargeCoordinates() throws {
        let original = HeatmapDataPoint(
            x: 9999.99,
            y: 9999.99,
            signalStrength: -30,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HeatmapDataPoint.self, from: data)

        #expect(abs(decoded.x - 9999.99) < 0.01)
        #expect(abs(decoded.y - 9999.99) < 0.01)
    }

    @Test("HeatmapDataPoint array Codable round-trip")
    func codableArrayRoundTrip() throws {
        let points = [
            HeatmapDataPoint(x: 10, y: 20, signalStrength: -40, timestamp: Date()),
            HeatmapDataPoint(x: 30, y: 40, signalStrength: -60, timestamp: Date()),
            HeatmapDataPoint(x: 50, y: 60, signalStrength: -80, timestamp: Date()),
        ]

        let data = try JSONEncoder().encode(points)
        let decoded = try JSONDecoder().decode([HeatmapDataPoint].self, from: data)

        #expect(decoded.count == 3)
        #expect(decoded[0].signalStrength == -40)
        #expect(decoded[1].signalStrength == -60)
        #expect(decoded[2].signalStrength == -80)
    }

    // MARK: - Init

    @Test("HeatmapDataPoint init stores all properties")
    func initStoresProperties() {
        let ts = Date(timeIntervalSinceReferenceDate: 500_000)
        let point = HeatmapDataPoint(x: 100.0, y: 200.0, signalStrength: -65, timestamp: ts)
        #expect(point.x == 100.0)
        #expect(point.y == 200.0)
        #expect(point.signalStrength == -65)
        #expect(point.timestamp == ts)
    }

    @Test("HeatmapDataPoint default timestamp is near now")
    func defaultTimestampIsNow() {
        let before = Date()
        let point = HeatmapDataPoint(x: 0, y: 0, signalStrength: -50)
        let after = Date()
        #expect(point.timestamp >= before)
        #expect(point.timestamp <= after)
    }
}

// MARK: - SignalLevel Tests

@Suite("SignalLevel")
struct SignalLevelTests {

    @Test("SignalLevel.from strong for -50 dBm")
    func strongAtMinus50() {
        #expect(SignalLevel.from(rssi: -50) == .strong)
    }

    @Test("SignalLevel.from strong for -30 dBm")
    func strongAtMinus30() {
        #expect(SignalLevel.from(rssi: -30) == .strong)
    }

    @Test("SignalLevel.from strong for 0 dBm")
    func strongAtZero() {
        #expect(SignalLevel.from(rssi: 0) == .strong)
    }

    @Test("SignalLevel.from fair for -51 dBm")
    func fairAtMinus51() {
        #expect(SignalLevel.from(rssi: -51) == .fair)
    }

    @Test("SignalLevel.from fair for -70 dBm")
    func fairAtMinus70() {
        #expect(SignalLevel.from(rssi: -70) == .fair)
    }

    @Test("SignalLevel.from weak for -71 dBm")
    func weakAtMinus71() {
        #expect(SignalLevel.from(rssi: -71) == .weak)
    }

    @Test("SignalLevel.from weak for -90 dBm")
    func weakAtMinus90() {
        #expect(SignalLevel.from(rssi: -90) == .weak)
    }

    @Test("SignalLevel hexColor values are non-empty")
    func hexColorNonEmpty() {
        #expect(!SignalLevel.strong.hexColor.isEmpty)
        #expect(!SignalLevel.fair.hexColor.isEmpty)
        #expect(!SignalLevel.weak.hexColor.isEmpty)
    }

    @Test("SignalLevel label values are non-empty")
    func labelNonEmpty() {
        #expect(SignalLevel.strong.label == "Strong")
        #expect(SignalLevel.fair.label == "Fair")
        #expect(SignalLevel.weak.label == "Weak")
    }
}

// MARK: - HeatmapMode Tests

@Suite("HeatmapMode")
struct HeatmapModeTests {

    @Test("HeatmapMode has all expected cases")
    func allCases() {
        #expect(HeatmapMode.allCases.count == 2)
        #expect(HeatmapMode.allCases.contains(.freeform))
        #expect(HeatmapMode.allCases.contains(.floorplan))
    }

    @Test("HeatmapMode rawValue is correct")
    func rawValues() {
        #expect(HeatmapMode.freeform.rawValue == "freeform")
        #expect(HeatmapMode.floorplan.rawValue == "floorplan")
    }

    @Test("HeatmapMode displayName is non-empty")
    func displayNames() {
        #expect(HeatmapMode.freeform.displayName == "Freeform")
        #expect(HeatmapMode.floorplan.displayName == "Floorplan")
    }

    @Test("HeatmapMode systemImage is non-empty")
    func systemImages() {
        #expect(!HeatmapMode.freeform.systemImage.isEmpty)
        #expect(!HeatmapMode.floorplan.systemImage.isEmpty)
    }

    @Test("HeatmapMode description is non-empty")
    func descriptions() {
        #expect(!HeatmapMode.freeform.description.isEmpty)
        #expect(!HeatmapMode.floorplan.description.isEmpty)
    }

    @Test("HeatmapMode Codable round-trip")
    func codableRoundTrip() throws {
        let original = HeatmapMode.floorplan
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HeatmapMode.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - HeatmapSurvey Tests

@Suite("HeatmapSurvey")
struct HeatmapSurveyTests {

    @Test("HeatmapSurvey init stores properties")
    func initStoresProperties() {
        let id = UUID()
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let survey = HeatmapSurvey(id: id, name: "Test Survey", mode: .freeform, createdAt: date)
        #expect(survey.id == id)
        #expect(survey.name == "Test Survey")
        #expect(survey.mode == .freeform)
        #expect(survey.createdAt == date)
        #expect(survey.dataPoints.isEmpty)
    }

    @Test("HeatmapSurvey averageSignal is nil when no data points")
    func averageSignalNilWhenEmpty() {
        let survey = HeatmapSurvey(name: "Empty")
        #expect(survey.averageSignal == nil)
    }

    @Test("HeatmapSurvey averageSignal computes correct average")
    func averageSignalComputed() {
        let points = [
            HeatmapDataPoint(x: 0, y: 0, signalStrength: -40),
            HeatmapDataPoint(x: 1, y: 1, signalStrength: -60),
            HeatmapDataPoint(x: 2, y: 2, signalStrength: -80),
        ]
        let survey = HeatmapSurvey(name: "Test", dataPoints: points)
        // (-40 + -60 + -80) / 3 = -60
        #expect(survey.averageSignal == -60)
    }

    @Test("HeatmapSurvey signalLevel is nil when no data points")
    func signalLevelNilWhenEmpty() {
        let survey = HeatmapSurvey(name: "Empty")
        #expect(survey.signalLevel == nil)
    }

    @Test("HeatmapSurvey signalLevel reflects averageSignal")
    func signalLevelReflectsAverage() {
        let strongPoints = [
            HeatmapDataPoint(x: 0, y: 0, signalStrength: -30),
            HeatmapDataPoint(x: 1, y: 1, signalStrength: -40),
        ]
        let survey = HeatmapSurvey(name: "Strong", dataPoints: strongPoints)
        // Average = -35, which is strong (>= -50)
        #expect(survey.signalLevel == .strong)
    }

    @Test("HeatmapSurvey Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let id = UUID()
        let points = [
            HeatmapDataPoint(x: 10, y: 20, signalStrength: -55, timestamp: Date()),
        ]
        let original = HeatmapSurvey(id: id, name: "Codable Test", mode: .floorplan, dataPoints: points)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HeatmapSurvey.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.name == "Codable Test")
        #expect(decoded.mode == .floorplan)
        #expect(decoded.dataPoints.count == 1)
        #expect(decoded.dataPoints.first?.signalStrength == -55)
    }
}

// MARK: - DistanceUnit Tests

@Suite("DistanceUnit")
struct DistanceUnitTests {

    @Test("feet displayName is ft")
    func feetDisplayName() {
        #expect(DistanceUnit.feet.displayName == "ft")
    }

    @Test("meters displayName is m")
    func metersDisplayName() {
        #expect(DistanceUnit.meters.displayName == "m")
    }

    @Test("feet to meters conversion")
    func feetToMeters() {
        let result = DistanceUnit.feet.convert(10, to: .meters)
        #expect(abs(result - 3.048) < 0.001)
    }

    @Test("meters to feet conversion")
    func metersToFeet() {
        let result = DistanceUnit.meters.convert(3.048, to: .feet)
        #expect(abs(result - 10.0) < 0.001)
    }

    @Test("same unit convert is identity")
    func sameUnitIdentity() {
        #expect(DistanceUnit.feet.convert(5, to: .feet) == 5)
    }
}

// MARK: - CalibrationScale Tests

@Suite("CalibrationScale")
struct CalibrationScaleTests {

    @Test("pixelsPerUnit computes correctly")
    func pixelsPerUnit() {
        let scale = CalibrationScale(pixelDistance: 200, realDistance: 10, unit: .feet)
        #expect(scale.pixelsPerUnit == 20.0)
    }

    @Test("realDistance(pixels:) converts correctly")
    func realDistanceFromPixels() {
        let scale = CalibrationScale(pixelDistance: 200, realDistance: 10, unit: .feet)
        #expect(scale.realDistance(pixels: 100) == 5.0)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = CalibrationScale(pixelDistance: 150.5, realDistance: 5.0, unit: .meters)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalibrationScale.self, from: data)
        #expect(decoded.pixelDistance == original.pixelDistance)
        #expect(decoded.realDistance == original.realDistance)
        #expect(decoded.unit == original.unit)
    }
}

// MARK: - HeatmapColorScheme Tests

@Suite("HeatmapColorScheme")
struct HeatmapColorSchemeTests {

    @Test("all cases exist")
    func allCases() {
        let cases = HeatmapColorScheme.allCases
        #expect(cases.contains(.thermal))
        #expect(cases.contains(.signal))
        #expect(cases.contains(.nebula))
        #expect(cases.contains(.arctic))
    }

    @Test("thermal has non-empty stop table")
    func thermalStops() {
        #expect(!HeatmapColorScheme.thermal.colorStops.isEmpty)
    }

    @Test("all schemes have at least 2 color stops")
    func allSchemesHaveStops() {
        for scheme in HeatmapColorScheme.allCases {
            #expect(scheme.colorStops.count >= 2, "scheme \(scheme.rawValue) needs ≥ 2 stops")
        }
    }

    @Test("Codable round-trip")
    func codable() throws {
        let data = try JSONEncoder().encode(HeatmapColorScheme.thermal)
        let decoded = try JSONDecoder().decode(HeatmapColorScheme.self, from: data)
        #expect(decoded == .thermal)
    }
}

// MARK: - HeatmapDisplayOverlay Tests

@Suite("HeatmapDisplayOverlay")
struct HeatmapDisplayOverlayTests {

    @Test("default contains gradient")
    func defaultContainsGradient() {
        let overlay = HeatmapDisplayOverlay.gradient
        #expect(overlay.contains(.gradient))
        #expect(!overlay.contains(.dots))
    }

    @Test("union works")
    func union() {
        let combo: HeatmapDisplayOverlay = [.gradient, .dots]
        #expect(combo.contains(.gradient))
        #expect(combo.contains(.dots))
        #expect(!combo.contains(.contour))
    }

    @Test("Codable round-trip")
    func codable() throws {
        let overlay: HeatmapDisplayOverlay = [.gradient, .contour]
        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(HeatmapDisplayOverlay.self, from: data)
        #expect(decoded == overlay)
    }
}

// MARK: - HeatmapSurvey calibration field tests

@Suite("HeatmapSurvey calibration")
struct HeatmapSurveyCalibratedTests {

    @Test("uncalibrated survey decodes without calibration field (backward compat)")
    func backwardCompatibility() throws {
        // Old JSON without calibration field
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Old Survey",
         "mode":"freeform","createdAt":0,"dataPoints":[]}
        """
        let survey = try JSONDecoder().decode(HeatmapSurvey.self, from: Data(json.utf8))
        #expect(survey.calibration == nil)
    }

    @Test("calibrated survey encodes and decodes calibration")
    func calibratedRoundTrip() throws {
        let scale = CalibrationScale(pixelDistance: 100, realDistance: 20, unit: .feet)
        var survey = HeatmapSurvey(name: "Test")
        survey.calibration = scale
        let data = try JSONEncoder().encode(survey)
        let decoded = try JSONDecoder().decode(HeatmapSurvey.self, from: data)
        #expect(decoded.calibration?.pixelDistance == 100)
        #expect(decoded.calibration?.unit == .feet)
    }
}
