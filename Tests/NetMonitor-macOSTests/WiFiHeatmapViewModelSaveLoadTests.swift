import Foundation
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - Project Save/Load Roundtrip

@MainActor
struct WiFiHeatmapViewModelSaveLoadTests {

    /// Regression guard for the v2.1 user-promise that surveys persist across
    /// relaunch. Only the Core `ProjectSaveLoadManager` was covered by tests;
    /// the VM-layer glue that assigns `measurementPoints` into the project on
    /// save and extracts them on load had no coverage.
    @Test("save/load roundtrip preserves measurement points and calibration")
    func saveLoadRoundTripPreservesMeasurementsAndCalibration() throws {
        // 1. Build a calibrated project with a handful of distinctive measurements.
        let source = WiFiHeatmapViewModel()
        try source.importFloorPlan(imageData: makeTestPNGData(), name: "RoundTripTest")
        source.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.2))
        source.addCalibrationPoint(at: CGPoint(x: 0.9, y: 0.2))
        source.completeCalibration(withDistance: 8.0)
        #expect(source.isCalibrated == true)

        source.measurementPoints = [
            MeasurementPoint(floorPlanX: 0.15, floorPlanY: 0.15, rssi: -42, ssid: "TestNet"),
            MeasurementPoint(floorPlanX: 0.55, floorPlanY: 0.55, rssi: -63, ssid: "TestNet"),
            MeasurementPoint(floorPlanX: 0.85, floorPlanY: 0.85, rssi: -81, ssid: "TestNet"),
        ]

        // 2. Write to a temp file.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heatmap-roundtrip-\(UUID().uuidString).netmonsurvey")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try source.saveProject(to: tempURL)
        #expect(FileManager.default.fileExists(atPath: tempURL.path))

        // 3. Load into a pristine VM.
        let target = WiFiHeatmapViewModel()
        try target.loadProject(from: tempURL)

        // 4. Measurements preserved by count, coordinates, and RSSI.
        #expect(target.measurementPoints.count == 3)
        #expect(target.measurementPoints.map(\.rssi) == [-42, -63, -81])
        #expect(target.measurementPoints.map(\.floorPlanX) == [0.15, 0.55, 0.85])
        #expect(target.measurementPoints.map(\.floorPlanY) == [0.15, 0.55, 0.85])

        // 5. Calibration preserved — floor plan retains its scaled dimensions
        //    and the VM re-enters the calibrated state on load.
        #expect(target.isCalibrated == true)
        #expect(target.surveyProject?.floorPlan.calibrationPoints?.count == 2)
    }

    /// If saveProject is called before a floor plan is imported, it should
    /// be a no-op rather than producing a malformed file. This protects the
    /// early-return guard in `saveProject(to:)`.
    @Test("saveProject is a no-op when no floor plan is loaded")
    func saveProjectWithoutFloorPlanIsNoOp() throws {
        let vm = WiFiHeatmapViewModel()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heatmap-empty-\(UUID().uuidString).netmonsurvey")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try vm.saveProject(to: tempURL)
        #expect(FileManager.default.fileExists(atPath: tempURL.path) == false)
    }
}
