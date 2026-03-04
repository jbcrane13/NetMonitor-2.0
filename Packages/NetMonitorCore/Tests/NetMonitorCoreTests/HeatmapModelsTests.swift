import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - SurveyProject Tests

@Suite("SurveyProject")
struct SurveyProjectTests {

    // VAL-FOUND-001: SurveyProject serialization round-trip
    @Test func fullRoundTrip() throws {
        let calibration1 = CalibrationPoint(pixelX: 100, pixelY: 200, realWorldX: 0.0, realWorldY: 0.0)
        let calibration2 = CalibrationPoint(pixelX: 500, pixelY: 200, realWorldX: 10.0, realWorldY: 0.0)
        let wall = WallSegment(startX: 0, startY: 0, endX: 10, endY: 0, thickness: 0.15)

        let floorPlan = FloorPlan(
            imageData: Data([0xFF, 0xD8, 0xFF]),
            widthMeters: 20.0,
            heightMeters: 15.0,
            pixelWidth: 1000,
            pixelHeight: 750,
            origin: .imported(URL(string: "file:///tmp/plan.png")!),
            calibrationPoints: [calibration1, calibration2],
            walls: [wall]
        )

        let point = MeasurementPoint(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            floorPlanX: 0.5,
            floorPlanY: 0.3,
            rssi: -55,
            noiseFloor: -90,
            snr: 35,
            ssid: "TestNetwork",
            bssid: "AA:BB:CC:DD:EE:FF",
            channel: 6,
            frequency: 2437,
            band: .band2_4GHz,
            linkSpeed: 72,
            downloadSpeed: 150.5,
            uploadSpeed: 50.2,
            latency: 12.3,
            connectedAPName: "Office-AP-1"
        )

        let metadata = SurveyMetadata(
            buildingName: "Main Office",
            floorNumber: 2,
            notes: "Second floor survey"
        )

        let project = SurveyProject(
            name: "Office Survey",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            floorPlan: floorPlan,
            measurementPoints: [point],
            surveyMode: .blueprint,
            metadata: metadata
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(project)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SurveyProject.self, from: data)

        #expect(decoded.id == project.id)
        #expect(decoded.name == project.name)
        #expect(decoded.createdAt == project.createdAt)
        #expect(decoded.surveyMode == project.surveyMode)
        #expect(decoded.metadata == project.metadata)
        #expect(decoded.floorPlan == project.floorPlan)
        #expect(decoded.measurementPoints.count == 1)
        #expect(decoded.measurementPoints[0] == point)
        #expect(decoded == project)
    }

    // VAL-FOUND-002: SurveyProject serialization with empty measurement points
    @Test func emptyMeasurementPoints() throws {
        let floorPlan = FloorPlan(
            imageData: Data([0x89, 0x50, 0x4E, 0x47]),
            widthMeters: 10.0,
            heightMeters: 8.0,
            pixelWidth: 800,
            pixelHeight: 600,
            origin: .drawn
        )

        let project = SurveyProject(
            name: "Empty Survey",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            floorPlan: floorPlan,
            measurementPoints: [],
            surveyMode: .blueprint,
            metadata: nil
        )

        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(SurveyProject.self, from: data)

        #expect(decoded.measurementPoints.isEmpty)
        #expect(decoded == project)
    }

    @Test func identifiable() {
        let floorPlan = FloorPlan(
            imageData: Data(),
            widthMeters: 10.0,
            heightMeters: 8.0,
            pixelWidth: 800,
            pixelHeight: 600,
            origin: .drawn
        )
        let project = SurveyProject(
            name: "Test",
            createdAt: Date(),
            floorPlan: floorPlan,
            measurementPoints: [],
            surveyMode: .blueprint,
            metadata: nil
        )
        // Identifiable conformance: id is UUID
        let _: UUID = project.id
        #expect(project.id == project.id)
    }
}

// MARK: - FloorPlan Tests

@Suite("FloorPlan")
struct FloorPlanTests {

    // VAL-FOUND-003: FloorPlan serialization with calibration data
    @Test func withCalibrationRoundTrip() throws {
        let cal1 = CalibrationPoint(pixelX: 100, pixelY: 200, realWorldX: 0.0, realWorldY: 0.0)
        let cal2 = CalibrationPoint(pixelX: 500, pixelY: 200, realWorldX: 10.0, realWorldY: 0.0)

        let floorPlan = FloorPlan(
            imageData: Data([0xFF, 0xD8, 0xFF]),
            widthMeters: 20.0,
            heightMeters: 15.0,
            pixelWidth: 1000,
            pixelHeight: 750,
            origin: .imported(URL(string: "file:///tmp/plan.png")!),
            calibrationPoints: [cal1, cal2],
            walls: nil
        )

        let data = try JSONEncoder().encode(floorPlan)
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: data)

        #expect(decoded.id == floorPlan.id)
        #expect(decoded.imageData == floorPlan.imageData)
        #expect(decoded.widthMeters == floorPlan.widthMeters)
        #expect(decoded.heightMeters == floorPlan.heightMeters)
        #expect(decoded.pixelWidth == floorPlan.pixelWidth)
        #expect(decoded.pixelHeight == floorPlan.pixelHeight)
        #expect(decoded.origin == floorPlan.origin)
        #expect(decoded.calibrationPoints?.count == 2)
        #expect(decoded.calibrationPoints?[0] == cal1)
        #expect(decoded.calibrationPoints?[1] == cal2)
        #expect(decoded == floorPlan)
    }

    // VAL-FOUND-004: FloorPlan serialization without calibration
    @Test func withoutCalibrationRoundTrip() throws {
        let floorPlan = FloorPlan(
            imageData: Data([0x89, 0x50]),
            widthMeters: 0,
            heightMeters: 0,
            pixelWidth: 800,
            pixelHeight: 600,
            origin: .drawn,
            calibrationPoints: nil,
            walls: nil
        )

        let data = try JSONEncoder().encode(floorPlan)
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: data)

        #expect(decoded.calibrationPoints == nil)
        #expect(decoded.widthMeters == 0)
        #expect(decoded.heightMeters == 0)
        #expect(decoded == floorPlan)
    }

    // VAL-FOUND-049: WallSegment serialization round-trip
    @Test func withWallsRoundTrip() throws {
        let wall1 = WallSegment(startX: 0, startY: 0, endX: 10, endY: 0, thickness: 0.15)
        let wall2 = WallSegment(startX: 10, startY: 0, endX: 10, endY: 8, thickness: 0.2)

        let floorPlan = FloorPlan(
            imageData: Data([0x89]),
            widthMeters: 10,
            heightMeters: 8,
            pixelWidth: 500,
            pixelHeight: 400,
            origin: .drawn,
            calibrationPoints: nil,
            walls: [wall1, wall2]
        )

        let data = try JSONEncoder().encode(floorPlan)
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: data)

        #expect(decoded.walls?.count == 2)
        #expect(decoded.walls?[0] == wall1)
        #expect(decoded.walls?[1] == wall2)
        #expect(decoded == floorPlan)
    }

    @Test func identifiable() {
        let floorPlan = FloorPlan(
            imageData: Data(),
            widthMeters: 10,
            heightMeters: 8,
            pixelWidth: 100,
            pixelHeight: 80,
            origin: .drawn
        )
        let _: UUID = floorPlan.id
        #expect(floorPlan.id == floorPlan.id)
    }
}

// MARK: - FloorPlanOrigin Tests

@Suite("FloorPlanOrigin")
struct FloorPlanOriginTests {

    // VAL-FOUND-005: FloorPlanOrigin enum serialization for all cases
    @Test func importedURLRoundTrip() throws {
        let url = URL(string: "file:///Users/test/Documents/plan.png")!
        let origin = FloorPlanOrigin.imported(url)

        let data = try JSONEncoder().encode(origin)
        let decoded = try JSONDecoder().decode(FloorPlanOrigin.self, from: data)

        #expect(decoded == origin)
        if case .imported(let decodedURL) = decoded {
            #expect(decodedURL == url)
        } else {
            Issue.record("Expected .imported case")
        }
    }

    @Test func arGeneratedRoundTrip() throws {
        let origin = FloorPlanOrigin.arGenerated

        let data = try JSONEncoder().encode(origin)
        let decoded = try JSONDecoder().decode(FloorPlanOrigin.self, from: data)

        #expect(decoded == origin)
    }

    @Test func drawnRoundTrip() throws {
        let origin = FloorPlanOrigin.drawn

        let data = try JSONEncoder().encode(origin)
        let decoded = try JSONDecoder().decode(FloorPlanOrigin.self, from: data)

        #expect(decoded == origin)
    }
}

// MARK: - MeasurementPoint Tests

@Suite("MeasurementPoint")
struct MeasurementPointTests {

    // VAL-FOUND-006: MeasurementPoint full-field serialization
    @Test func allFieldsRoundTrip() throws {
        let point = MeasurementPoint(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            floorPlanX: 0.75,
            floorPlanY: 0.25,
            rssi: -42,
            noiseFloor: -95,
            snr: 53,
            ssid: "OfficeWiFi",
            bssid: "11:22:33:44:55:66",
            channel: 36,
            frequency: 5180,
            band: .band5GHz,
            linkSpeed: 866,
            downloadSpeed: 250.7,
            uploadSpeed: 125.3,
            latency: 5.2,
            connectedAPName: "AP-Floor2-NE"
        )

        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(MeasurementPoint.self, from: data)

        #expect(decoded.id == point.id)
        #expect(decoded.timestamp == point.timestamp)
        #expect(decoded.floorPlanX == point.floorPlanX)
        #expect(decoded.floorPlanY == point.floorPlanY)
        #expect(decoded.rssi == point.rssi)
        #expect(decoded.noiseFloor == point.noiseFloor)
        #expect(decoded.snr == point.snr)
        #expect(decoded.ssid == point.ssid)
        #expect(decoded.bssid == point.bssid)
        #expect(decoded.channel == point.channel)
        #expect(decoded.frequency == point.frequency)
        #expect(decoded.band == point.band)
        #expect(decoded.linkSpeed == point.linkSpeed)
        #expect(decoded.downloadSpeed == point.downloadSpeed)
        #expect(decoded.uploadSpeed == point.uploadSpeed)
        #expect(decoded.latency == point.latency)
        #expect(decoded.connectedAPName == point.connectedAPName)
        #expect(decoded == point)
    }

    // VAL-FOUND-007: MeasurementPoint minimal-field serialization
    @Test func minimalFieldsRoundTrip() throws {
        let point = MeasurementPoint(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            floorPlanX: 0.0,
            floorPlanY: 1.0,
            rssi: -70
        )

        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(MeasurementPoint.self, from: data)

        #expect(decoded.noiseFloor == nil)
        #expect(decoded.snr == nil)
        #expect(decoded.ssid == nil)
        #expect(decoded.bssid == nil)
        #expect(decoded.channel == nil)
        #expect(decoded.frequency == nil)
        #expect(decoded.band == nil)
        #expect(decoded.linkSpeed == nil)
        #expect(decoded.downloadSpeed == nil)
        #expect(decoded.uploadSpeed == nil)
        #expect(decoded.latency == nil)
        #expect(decoded.connectedAPName == nil)
        #expect(decoded == point)
    }

    // VAL-FOUND-047: MeasurementPoint normalized coordinates
    @Test func normalizedCoordinates() {
        // Valid range 0.0-1.0
        let point = MeasurementPoint(
            timestamp: Date(),
            floorPlanX: 0.5,
            floorPlanY: 0.5,
            rssi: -50
        )
        #expect(point.floorPlanX >= 0.0)
        #expect(point.floorPlanX <= 1.0)
        #expect(point.floorPlanY >= 0.0)
        #expect(point.floorPlanY <= 1.0)
    }

    @Test func identifiable() {
        let point = MeasurementPoint(
            timestamp: Date(),
            floorPlanX: 0.5,
            floorPlanY: 0.5,
            rssi: -50
        )
        let _: UUID = point.id
        #expect(point.id == point.id)
    }
}

// MARK: - HeatmapVisualization Tests

@Suite("HeatmapVisualization")
struct HeatmapVisualizationTests {

    // VAL-FOUND-008: HeatmapVisualization enum serialization
    @Test func allCasesRoundTrip() throws {
        for viz in HeatmapVisualization.allCases {
            let data = try JSONEncoder().encode(viz)
            let decoded = try JSONDecoder().decode(HeatmapVisualization.self, from: data)
            #expect(decoded == viz, "Failed round-trip for \(viz)")
        }
    }

    @Test func stableRawValues() {
        #expect(HeatmapVisualization.signalStrength.rawValue == "signalStrength")
        #expect(HeatmapVisualization.signalToNoise.rawValue == "signalToNoise")
        #expect(HeatmapVisualization.downloadSpeed.rawValue == "downloadSpeed")
        #expect(HeatmapVisualization.uploadSpeed.rawValue == "uploadSpeed")
        #expect(HeatmapVisualization.latency.rawValue == "latency")
    }

    @Test func allCasesCount() {
        #expect(HeatmapVisualization.allCases.count == 5)
    }
}

// MARK: - WiFiBand Tests (Heatmap context)

@Suite("WiFiBand Codable")
struct WiFiBandCodableTests {

    // VAL-FOUND-009: WiFiBand enum serialization
    @Test func allCasesRoundTrip() throws {
        for band in WiFiBand.allCases {
            let data = try JSONEncoder().encode(band)
            let decoded = try JSONDecoder().decode(WiFiBand.self, from: data)
            #expect(decoded == band, "Failed round-trip for \(band)")
        }
    }

    @Test func stableRawValues() {
        #expect(WiFiBand.band2_4GHz.rawValue == "2.4 GHz")
        #expect(WiFiBand.band5GHz.rawValue == "5 GHz")
        #expect(WiFiBand.band6GHz.rawValue == "6 GHz")
    }
}

// MARK: - SurveyMode Tests

@Suite("SurveyMode")
struct SurveyModeTests {

    // VAL-FOUND-010: SurveyMode enum serialization
    @Test func allCasesRoundTrip() throws {
        for mode in SurveyMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(SurveyMode.self, from: data)
            #expect(decoded == mode, "Failed round-trip for \(mode)")
        }
    }

    @Test func stableRawValues() {
        #expect(SurveyMode.blueprint.rawValue == "blueprint")
        #expect(SurveyMode.arAssisted.rawValue == "arAssisted")
        #expect(SurveyMode.arContinuous.rawValue == "arContinuous")
    }
}

// MARK: - SurveyMetadata Tests

@Suite("SurveyMetadata")
struct SurveyMetadataTests {

    // VAL-FOUND-011: SurveyMetadata serialization
    @Test func roundTrip() throws {
        let metadata = SurveyMetadata(
            buildingName: "Main Office",
            floorNumber: 3,
            notes: "Third floor, west wing"
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(SurveyMetadata.self, from: data)

        #expect(decoded.buildingName == "Main Office")
        #expect(decoded.floorNumber == 3)
        #expect(decoded.notes == "Third floor, west wing")
        #expect(decoded == metadata)
    }

    @Test func nilFieldsRoundTrip() throws {
        let metadata = SurveyMetadata(buildingName: nil, floorNumber: nil, notes: nil)

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(SurveyMetadata.self, from: data)

        #expect(decoded.buildingName == nil)
        #expect(decoded.floorNumber == nil)
        #expect(decoded.notes == nil)
        #expect(decoded == metadata)
    }
}

// MARK: - CalibrationPoint Tests

@Suite("CalibrationPoint")
struct CalibrationPointTests {

    // VAL-FOUND-012: CalibrationPoint serialization
    @Test func roundTrip() throws {
        let point1 = CalibrationPoint(pixelX: 100.0, pixelY: 200.0, realWorldX: 0.0, realWorldY: 0.0)
        let point2 = CalibrationPoint(pixelX: 900.0, pixelY: 200.0, realWorldX: 20.0, realWorldY: 0.0)

        let points = [point1, point2]
        let data = try JSONEncoder().encode(points)
        let decoded = try JSONDecoder().decode([CalibrationPoint].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded[0] == point1)
        #expect(decoded[1] == point2)
        #expect(decoded[0].pixelX == 100.0)
        #expect(decoded[0].pixelY == 200.0)
        #expect(decoded[0].realWorldX == 0.0)
        #expect(decoded[0].realWorldY == 0.0)
    }
}

// MARK: - WallSegment Tests

@Suite("WallSegment")
struct WallSegmentTests {

    @Test func roundTrip() throws {
        let wall = WallSegment(startX: 1.5, startY: 2.0, endX: 5.5, endY: 2.0, thickness: 0.15)

        let data = try JSONEncoder().encode(wall)
        let decoded = try JSONDecoder().decode(WallSegment.self, from: data)

        #expect(decoded.startX == 1.5)
        #expect(decoded.startY == 2.0)
        #expect(decoded.endX == 5.5)
        #expect(decoded.endY == 2.0)
        #expect(decoded.thickness == 0.15)
        #expect(decoded == wall)
    }
}

// MARK: - Sendable Conformance Tests

@Suite("Sendable Conformance")
struct SendableConformanceTests {

    // VAL-FOUND-013: All model types conform to Sendable
    // This test verifies Sendable conformance by passing values across concurrency boundaries.
    // If any type doesn't conform to Sendable, this won't compile under strict concurrency.
    @Test func allTypesAreSendable() async {
        let calibration = CalibrationPoint(pixelX: 0, pixelY: 0, realWorldX: 0, realWorldY: 0)
        let wall = WallSegment(startX: 0, startY: 0, endX: 1, endY: 1, thickness: 0.1)
        let metadata = SurveyMetadata(buildingName: "Test", floorNumber: 1, notes: nil)
        let origin = FloorPlanOrigin.drawn
        let mode = SurveyMode.blueprint
        let viz = HeatmapVisualization.signalStrength

        let floorPlan = FloorPlan(
            imageData: Data(),
            widthMeters: 10,
            heightMeters: 8,
            pixelWidth: 100,
            pixelHeight: 80,
            origin: origin,
            calibrationPoints: [calibration],
            walls: [wall]
        )

        let point = MeasurementPoint(
            timestamp: Date(),
            floorPlanX: 0.5,
            floorPlanY: 0.5,
            rssi: -50
        )

        let project = SurveyProject(
            name: "Test",
            createdAt: Date(),
            floorPlan: floorPlan,
            measurementPoints: [point],
            surveyMode: mode,
            metadata: metadata
        )

        // Send across concurrency boundary to verify Sendable
        await Task.detached {
            let _: CalibrationPoint = calibration
            let _: WallSegment = wall
            let _: SurveyMetadata = metadata
            let _: FloorPlanOrigin = origin
            let _: SurveyMode = mode
            let _: HeatmapVisualization = viz
            let _: FloorPlan = floorPlan
            let _: MeasurementPoint = point
            let _: SurveyProject = project
        }.value
    }
}
