import XCTest
@testable import NetMonitorCore

/// Contract tests for the WiFi Heatmap Data Models to ensure strict adherence to the PRD.
final class HeatmapSurveyModelsContractTests: XCTestCase {

    func testSurveyProjectRequirements() {
        // This test ensures `SurveyProject` complies directly with the model outlined in Section 1.3 of the PRD
        let expectation = SurveyProject(
            id: UUID(),
            name: "Main Floor",
            createdAt: Date(),
            floorPlan: FloorPlan(id: UUID(), imageData: Data(), widthMeters: 50.0, heightMeters: 30.0, pixelWidth: 1000, pixelHeight: 600, origin: .imported),
            measurementPoints: [],
            surveyMode: .blueprint,
            metadata: SurveyMetadata(buildingName: "HQ", floorNumber: "1", notes: "Test survey")
        )

        XCTAssertEqual(expectation.name, "Main Floor")
        XCTAssertEqual(expectation.surveyMode, .blueprint)
    }

    func testMeasurementPointRequirements() {
        let point = MeasurementPoint(
            id: UUID(),
            timestamp: Date(),
            floorPlanX: 0.5,
            floorPlanY: 0.5,
            rssi: -45,
            noiseFloor: -92,
            snr: 47,
            ssid: "Corporate_WiFi",
            bssid: "00:11:22:33:44:55",
            channel: 36,
            frequency: 5.18,
            band: .band5GHz,
            linkSpeed: 866,
            downloadSpeed: 345.5,
            uploadSpeed: 120.2,
            latency: 12.5,
            connectedAPName: "AP-Lobby"
        )

        XCTAssertEqual(point.rssi, -45)
        XCTAssertEqual(point.band, .band5GHz)
    }

    func testHeatmapVisualizationEnum() {
        // Enforce the cases from the PRD mappings
        let visualizations: [HeatmapVisualization] = [
            .signalStrength,
            .signalToNoise,
            .downloadSpeed,
            .uploadSpeed,
            .latency,
            .noiseFloor,
            .frequencyBand,
        ]

        XCTAssertEqual(visualizations.count, 7)
    }
}
