import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - Blueprint Round-Trip Contract Tests

/// Contract tests validating that heatmap survey data encoded on iOS can be
/// decoded by macOS-side code (and vice versa). Both platforms share the same
/// Codable models from NetMonitorCore, so the contract is: encode with
/// JSONEncoder → decode with JSONDecoder → all fields preserved.
///
/// Tests cover SurveyProject (the .netmonsurvey bundle format),
/// BlueprintProject (the .netmonblueprint import format), and cross-model
/// scenarios with multiple floors and measurement points.
struct BlueprintRoundTripContractTests {

    // MARK: - Helpers

    private static func makeFloorPlan(
        imageData: Data = Data([0x89, 0x50, 0x4E, 0x47]),
        widthMeters: Double = 12.0,
        heightMeters: Double = 8.0,
        pixelWidth: Int = 1200,
        pixelHeight: Int = 800,
        origin: FloorPlanOrigin = .imported,
        calibrationPoints: [CalibrationPoint]? = nil
    ) -> FloorPlan {
        FloorPlan(
            imageData: imageData,
            widthMeters: widthMeters,
            heightMeters: heightMeters,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            origin: origin,
            calibrationPoints: calibrationPoints
        )
    }

    private static func makeMeasurementPoint(
        x: Double = 0.5,
        y: Double = 0.5,
        rssi: Int = -55,
        ssid: String = "CorpWiFi",
        bssid: String = "AA:BB:CC:DD:EE:FF",
        channel: Int = 36,
        band: WiFiBand = .band5GHz
    ) -> MeasurementPoint {
        MeasurementPoint(
            floorPlanX: x,
            floorPlanY: y,
            rssi: rssi,
            noiseFloor: -90,
            snr: rssi - -90,
            ssid: ssid,
            bssid: bssid,
            channel: channel,
            frequency: 5180,
            band: band,
            linkSpeed: 866,
            downloadSpeed: 245.5,
            uploadSpeed: 92.1,
            latency: 4.2,
            connectedAPName: "AP-Floor2"
        )
    }

    // MARK: - SurveyProject Round-Trip

    @Test("SurveyProject with measurements survives JSON round-trip with all fields intact")
    func surveyProjectFullRoundTrip() throws {
        let points = [
            Self.makeMeasurementPoint(x: 0.1, y: 0.2, rssi: -42, channel: 1, band: .band2_4GHz),
            Self.makeMeasurementPoint(x: 0.5, y: 0.5, rssi: -55, channel: 36, band: .band5GHz),
            Self.makeMeasurementPoint(x: 0.9, y: 0.8, rssi: -72, channel: 149, band: .band5GHz),
        ]

        let floorPlan = Self.makeFloorPlan(
            origin: .arGenerated,
            calibrationPoints: nil
        )

        let original = SurveyProject(
            name: "Office Wi-Fi Survey",
            floorPlan: floorPlan,
            measurementPoints: points,
            surveyMode: .arAssisted,
            metadata: SurveyMetadata(
                buildingName: "HQ Building",
                floorNumber: "2",
                notes: "Conference room coverage check"
            )
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(SurveyProject.self, from: encoded)

        // Identity
        #expect(decoded.id == original.id)
        #expect(decoded.name == "Office Wi-Fi Survey")
        #expect(decoded.surveyMode == .arAssisted)

        // Metadata
        #expect(decoded.metadata.buildingName == "HQ Building")
        #expect(decoded.metadata.floorNumber == "2")
        #expect(decoded.metadata.notes == "Conference room coverage check")

        // Floor plan
        #expect(decoded.floorPlan.widthMeters == 12.0)
        #expect(decoded.floorPlan.heightMeters == 8.0)
        #expect(decoded.floorPlan.pixelWidth == 1200)
        #expect(decoded.floorPlan.pixelHeight == 800)
        #expect(decoded.floorPlan.origin == .arGenerated)
        #expect(decoded.floorPlan.imageData == Data([0x89, 0x50, 0x4E, 0x47]))

        // Measurement points count and order
        #expect(decoded.measurementPoints.count == 3)
        #expect(decoded.measurementPoints[0].rssi == -42)
        #expect(decoded.measurementPoints[1].rssi == -55)
        #expect(decoded.measurementPoints[2].rssi == -72)

        // Deep field check on first point
        let point = decoded.measurementPoints[0]
        #expect(point.floorPlanX == 0.1)
        #expect(point.floorPlanY == 0.2)
        #expect(point.band == .band2_4GHz)
        #expect(point.channel == 1)
        #expect(point.ssid == "CorpWiFi")
        #expect(point.bssid == "AA:BB:CC:DD:EE:FF")
        #expect(point.noiseFloor == -90)
        #expect(point.downloadSpeed == 245.5)
        #expect(point.uploadSpeed == 92.1)
        #expect(point.latency == 4.2)
        #expect(point.connectedAPName == "AP-Floor2")
    }

    @Test("SurveyProject with empty measurement points round-trips correctly")
    func surveyProjectEmptyMeasurements() throws {
        let original = SurveyProject(
            name: "Empty Survey",
            floorPlan: Self.makeFloorPlan()
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SurveyProject.self, from: encoded)

        #expect(decoded.id == original.id)
        #expect(decoded.measurementPoints.isEmpty)
        #expect(decoded.surveyMode == .blueprint)
    }

    // MARK: - BlueprintProject Round-Trip

    @Test("BlueprintProject with multiple floors and room labels round-trips correctly")
    func blueprintProjectMultiFloor() throws {
        let roomLabel1 = RoomLabel(text: "Living Room", normalizedX: 0.3, normalizedY: 0.4)
        let roomLabel2 = RoomLabel(text: "Kitchen", normalizedX: 0.7, normalizedY: 0.6)
        let wall = WallSegment(startX: 0, startY: 5, endX: 10, endY: 5, thickness: 0.2)

        let floor1 = BlueprintFloor(
            label: "Ground Floor",
            floorNumber: 1,
            svgData: Data("<svg>floor1</svg>".utf8),
            widthMeters: 15.0,
            heightMeters: 10.0,
            roomLabels: [roomLabel1, roomLabel2],
            wallSegments: [wall]
        )

        let floor2 = BlueprintFloor(
            label: "Second Floor",
            floorNumber: 2,
            svgData: Data("<svg>floor2</svg>".utf8),
            widthMeters: 15.0,
            heightMeters: 10.0,
            roomLabels: [],
            wallSegments: []
        )

        let original = BlueprintProject(
            name: "Home Blueprint",
            floors: [floor1, floor2],
            metadata: BlueprintMetadata(
                buildingName: "My House",
                address: "123 Main St",
                notes: "Scanned with iPhone 16 Pro",
                scanDeviceModel: "iPhone16,2",
                hasLiDAR: true
            )
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlueprintProject.self, from: encoded)

        // Top-level
        #expect(decoded.id == original.id)
        #expect(decoded.name == "Home Blueprint")
        #expect(decoded.floors.count == 2)

        // Metadata
        #expect(decoded.metadata.buildingName == "My House")
        #expect(decoded.metadata.address == "123 Main St")
        #expect(decoded.metadata.scanDeviceModel == "iPhone16,2")
        #expect(decoded.metadata.hasLiDAR == true)

        // Floor 1
        let decodedFloor1 = decoded.floors[0]
        #expect(decodedFloor1.label == "Ground Floor")
        #expect(decodedFloor1.floorNumber == 1)
        #expect(decodedFloor1.widthMeters == 15.0)
        #expect(decodedFloor1.heightMeters == 10.0)
        #expect(String(data: decodedFloor1.svgData, encoding: .utf8) == "<svg>floor1</svg>")
        #expect(decodedFloor1.roomLabels.count == 2)
        #expect(decodedFloor1.roomLabels[0].text == "Living Room")
        #expect(decodedFloor1.roomLabels[0].normalizedX == 0.3)
        #expect(decodedFloor1.roomLabels[1].text == "Kitchen")
        #expect(decodedFloor1.wallSegments.count == 1)
        #expect(decodedFloor1.wallSegments[0].thickness == 0.2)

        // Floor 2
        let decodedFloor2 = decoded.floors[1]
        #expect(decodedFloor2.label == "Second Floor")
        #expect(decodedFloor2.floorNumber == 2)
        #expect(decodedFloor2.roomLabels.isEmpty)
    }

    // MARK: - Cross-Platform Date Encoding

    @Test("SurveyProject createdAt timestamp survives round-trip with sub-second precision")
    func timestampPrecision() throws {
        let now = Date()
        let original = SurveyProject(
            name: "Timestamp Test",
            createdAt: now,
            floorPlan: Self.makeFloorPlan()
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SurveyProject.self, from: encoded)

        // Date round-trip through Codable should be exact (both use timeIntervalSinceReferenceDate)
        #expect(decoded.createdAt == original.createdAt)
    }

    @Test("MeasurementPoint timestamps survive round-trip")
    func measurementTimestamps() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let point = MeasurementPoint(timestamp: timestamp, rssi: -50)

        let encoded = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(MeasurementPoint.self, from: encoded)

        #expect(decoded.timestamp == timestamp)
    }

    // MARK: - FloorPlan with Calibration Points

    @Test("FloorPlan with calibration points and walls survives round-trip")
    func floorPlanWithCalibration() throws {
        let cal1 = CalibrationPoint(pixelX: 100, pixelY: 200, realWorldX: 0, realWorldY: 0)
        let cal2 = CalibrationPoint(pixelX: 700, pixelY: 200, realWorldX: 10, realWorldY: 0)
        let wall = WallSegment(startX: 0, startY: 0, endX: 12, endY: 0, thickness: 0.15)

        let original = FloorPlan(
            imageData: Data(repeating: 0xAB, count: 64),
            widthMeters: 12.0,
            heightMeters: 8.0,
            pixelWidth: 800,
            pixelHeight: 533,
            origin: .drawn,
            calibrationPoints: [cal1, cal2],
            walls: [wall]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FloorPlan.self, from: encoded)

        #expect(decoded.calibrationPoints?.count == 2)
        #expect(decoded.calibrationPoints?[0].pixelX == 100)
        #expect(decoded.calibrationPoints?[0].realWorldX == 0)
        #expect(decoded.calibrationPoints?[1].pixelX == 700)
        #expect(decoded.calibrationPoints?[1].realWorldX == 10)
        #expect(decoded.walls?.count == 1)
        #expect(decoded.walls?[0].endX == 12)
        #expect(decoded.origin == .drawn)
    }

    // MARK: - All SurveyMode Values

    @Test("All SurveyMode values survive round-trip through SurveyProject encoding")
    func allSurveyModesRoundTrip() throws {
        for mode in SurveyMode.allCases {
            let project = SurveyProject(
                name: "Mode Test",
                floorPlan: Self.makeFloorPlan(),
                surveyMode: mode
            )
            let encoded = try JSONEncoder().encode(project)
            let decoded = try JSONDecoder().decode(SurveyProject.self, from: encoded)
            #expect(decoded.surveyMode == mode, "SurveyMode.\(mode) failed round-trip")
        }
    }
}
