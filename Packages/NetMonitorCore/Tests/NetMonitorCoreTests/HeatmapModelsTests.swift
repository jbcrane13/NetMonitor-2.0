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
