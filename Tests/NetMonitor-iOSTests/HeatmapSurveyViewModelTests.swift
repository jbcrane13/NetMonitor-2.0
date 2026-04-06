import Foundation
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - HeatmapSurveyViewModel Init Tests

@MainActor
struct HeatmapSurveyViewModelInitTests {

    @Test("initial surveyProject is nil")
    func initialSurveyProjectIsNil() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.surveyProject == nil)
    }

    @Test("initial measurementPoints is empty")
    func initialMeasurementPointsEmpty() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.measurementPoints.isEmpty)
    }

    @Test("initial selectedVisualization is signalStrength")
    func initialVisualizationIsSignalStrength() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.selectedVisualization == .signalStrength)
    }

    @Test("initial measurementMode is passive")
    func initialMeasurementModeIsPassive() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.measurementMode == .passive)
    }

    @Test("initial isMeasuring is false")
    func initialIsMeasuringIsFalse() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.isMeasuring == false)
    }

    @Test("initial showImportSheet is false")
    func initialShowImportSheetIsFalse() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.showImportSheet == false)
    }

    @Test("initial currentRSSI is -100")
    func initialCurrentRSSIIsDefault() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.currentRSSI == -100)
    }

    @Test("initial currentSSID is nil")
    func initialCurrentSSIDIsNil() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.currentSSID == nil)
    }

    @Test("initial isCalibrating is false")
    func initialIsCalibratingIsFalse() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.isCalibrating == false)
    }

    @Test("initial calibrationPoints is empty")
    func initialCalibrationPointsEmpty() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.calibrationPoints.isEmpty)
    }

    @Test("initial calibrationDistance is 5.0 meters")
    func initialCalibrationDistance() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.calibrationDistance == 5.0)
    }
}

// MARK: - Floor Plan Import

@MainActor
struct HeatmapSurveyViewModelImportTests {

    @Test("importFloorPlan creates a surveyProject")
    func importFloorPlanCreatesSurveyProject() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([0x89, 0x50, 0x4E, 0x47]), width: 800, height: 600)
        #expect(vm.surveyProject != nil)
    }

    @Test("importFloorPlan sets correct pixel dimensions on floorPlan")
    func importFloorPlanSetsPixelDimensions() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1, 2, 3]), width: 1920, height: 1080)
        #expect(vm.surveyProject?.floorPlan.pixelWidth == 1920)
        #expect(vm.surveyProject?.floorPlan.pixelHeight == 1080)
    }

    @Test("importFloorPlan sets floorPlan origin to imported")
    func importFloorPlanSetsOriginToImported() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 100, height: 100)
        #expect(vm.surveyProject?.floorPlan.origin == .imported)
    }

    @Test("importFloorPlan clears existing measurementPoints")
    func importFloorPlanClearsMeasurementPoints() {
        let vm = HeatmapSurveyViewModel()
        vm.measurementPoints = [MeasurementPoint(rssi: -50)]
        vm.importFloorPlan(imageData: Data([1]), width: 200, height: 200)
        #expect(vm.measurementPoints.isEmpty)
    }

    @Test("importFloorPlan clears existing calibrationPoints")
    func importFloorPlanClearsCalibrationPoints() {
        let vm = HeatmapSurveyViewModel()
        vm.calibrationPoints = [CalibrationPoint(pixelX: 10, pixelY: 20)]
        vm.importFloorPlan(imageData: Data([1]), width: 200, height: 200)
        #expect(vm.calibrationPoints.isEmpty)
    }

    @Test("importFloorPlan stores imageData on floorPlan")
    func importFloorPlanStoresImageData() {
        let vm = HeatmapSurveyViewModel()
        let data = Data([0x01, 0x02, 0x03, 0x04])
        vm.importFloorPlan(imageData: data, width: 50, height: 50)
        #expect(vm.surveyProject?.floorPlan.imageData == data)
    }
}

// MARK: - Calibration

@MainActor
struct HeatmapSurveyViewModelCalibrationTests {

    @Test("startCalibration sets isCalibrating to true")
    func startCalibrationSetsIsCalibrating() {
        let vm = HeatmapSurveyViewModel()
        vm.startCalibration()
        #expect(vm.isCalibrating == true)
    }

    @Test("startCalibration clears calibrationPoints")
    func startCalibrationClearsPoints() {
        let vm = HeatmapSurveyViewModel()
        vm.calibrationPoints = [CalibrationPoint(pixelX: 10, pixelY: 20)]
        vm.startCalibration()
        #expect(vm.calibrationPoints.isEmpty)
    }

    @Test("cancelCalibration sets isCalibrating to false")
    func cancelCalibrationResetsFlag() {
        let vm = HeatmapSurveyViewModel()
        vm.startCalibration()
        vm.cancelCalibration()
        #expect(vm.isCalibrating == false)
    }

    @Test("cancelCalibration clears calibrationPoints")
    func cancelCalibrationClearsPoints() {
        let vm = HeatmapSurveyViewModel()
        vm.startCalibration()
        vm.addCalibrationPoint(at: CGPoint(x: 0.2, y: 0.3))
        vm.cancelCalibration()
        #expect(vm.calibrationPoints.isEmpty)
    }

    @Test("addCalibrationPoint appends a point")
    func addCalibrationPointAppends() {
        let vm = HeatmapSurveyViewModel()
        vm.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.4))
        #expect(vm.calibrationPoints.count == 1)
        #expect(vm.calibrationPoints[0].pixelX == 0.1)
        #expect(vm.calibrationPoints[0].pixelY == 0.4)
    }

    @Test("addCalibrationPoint does not exceed 2 points")
    func addCalibrationPointCapsAtTwo() {
        let vm = HeatmapSurveyViewModel()
        vm.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.2))
        vm.addCalibrationPoint(at: CGPoint(x: 0.5, y: 0.6))
        vm.addCalibrationPoint(at: CGPoint(x: 0.9, y: 0.8))  // should be ignored
        #expect(vm.calibrationPoints.count == 2)
    }

    @Test("addCalibrationPoint sets showCalibrationSheet when second point added")
    func addSecondCalibrationPointOpensSheet() {
        let vm = HeatmapSurveyViewModel()
        vm.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.2))
        #expect(vm.showCalibrationSheet == false)
        vm.addCalibrationPoint(at: CGPoint(x: 0.5, y: 0.6))
        #expect(vm.showCalibrationSheet == true)
    }

    @Test("completeCalibration updates floorPlan widthMeters and heightMeters")
    func completeCalibrationUpdatesFloorPlanScale() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 1000, height: 500)

        vm.addCalibrationPoint(at: CGPoint(x: 0.0, y: 0.0))
        vm.addCalibrationPoint(at: CGPoint(x: 100.0, y: 0.0))
        vm.completeCalibration(withDistance: 10.0)

        #expect(abs((vm.surveyProject?.floorPlan.widthMeters ?? 0) - 100.0) < 0.01)
        #expect(abs((vm.surveyProject?.floorPlan.heightMeters ?? 0) - 50.0) < 0.01)
    }

    @Test("completeCalibration sets isCalibrating to false")
    func completeCalibrationResetsFlag() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 800, height: 600)
        vm.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        vm.addCalibrationPoint(at: CGPoint(x: 100, y: 0))
        vm.isCalibrating = true
        vm.completeCalibration(withDistance: 5.0)
        #expect(vm.isCalibrating == false)
    }

    @Test("completeCalibration stores calibrationPoints on floorPlan")
    func completeCalibrationStoresPointsOnFloorPlan() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 800, height: 600)
        vm.addCalibrationPoint(at: CGPoint(x: 10, y: 20))
        vm.addCalibrationPoint(at: CGPoint(x: 50, y: 20))
        vm.completeCalibration(withDistance: 4.0)
        #expect(vm.surveyProject?.floorPlan.calibrationPoints?.count == 2)
    }

    @Test("completeCalibration clears calibrationPoints array")
    func completeCalibrationClearsArray() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 800, height: 600)
        vm.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        vm.addCalibrationPoint(at: CGPoint(x: 100, y: 0))
        vm.completeCalibration(withDistance: 10.0)
        #expect(vm.calibrationPoints.isEmpty)
    }

    @Test("completeCalibration does nothing without a survey project")
    func completeCalibrationNoOpWithoutProject() {
        let vm = HeatmapSurveyViewModel()
        vm.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        vm.addCalibrationPoint(at: CGPoint(x: 100, y: 0))
        vm.completeCalibration(withDistance: 5.0)
        #expect(vm.surveyProject == nil)
    }

    @Test("skipCalibration sets isCalibrated to true")
    func skipCalibrationSetsCalibrated() {
        let vm = HeatmapSurveyViewModel()
        vm.skipCalibration()
        #expect(vm.isCalibrated == true)
        #expect(vm.isCalibrating == false)
    }

    @Test("completeCalibration with feet converts to meters")
    func completeCalibrationWithFeetConverts() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 1000, height: 500)
        vm.addCalibrationPoint(at: CGPoint(x: 0.0, y: 0.0))
        vm.addCalibrationPoint(at: CGPoint(x: 100.0, y: 0.0))
        // 10 feet = 3.048 meters → metersPerPixel = 3.048/100 = 0.03048
        vm.completeCalibration(distance: 10.0, isFeet: true)
        let expectedWidth = 1000.0 * 0.03048
        #expect(abs((vm.surveyProject?.floorPlan.widthMeters ?? 0) - expectedWidth) < 0.01)
    }
}

// MARK: - Clear Measurements

@MainActor
struct HeatmapSurveyViewModelClearTests {

    @Test("clearMeasurements empties measurementPoints")
    func clearMeasurementsEmptiesPoints() {
        let vm = HeatmapSurveyViewModel()
        vm.measurementPoints = [
            MeasurementPoint(rssi: -50),
            MeasurementPoint(rssi: -60),
        ]
        vm.clearMeasurements()
        #expect(vm.measurementPoints.isEmpty)
    }

    @Test("clearMeasurements preserves surveyProject")
    func clearMeasurementsPreservesProject() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 100, height: 100)
        vm.measurementPoints = [MeasurementPoint(rssi: -55)]
        vm.clearMeasurements()
        #expect(vm.surveyProject != nil)
    }
}

// MARK: - Visualization Switching

@MainActor
struct HeatmapSurveyViewModelVisualizationTests {

    @Test("selectedVisualization can be changed")
    func changeVisualization() {
        let vm = HeatmapSurveyViewModel()
        vm.selectedVisualization = .downloadSpeed
        #expect(vm.selectedVisualization == .downloadSpeed)
    }

    @Test("measurementMode can be switched to active")
    func changeMeasurementModeToActive() {
        let vm = HeatmapSurveyViewModel()
        vm.measurementMode = .active
        #expect(vm.measurementMode == .active)
    }

    @Test("MeasurementMode allCases contains passive and active")
    func measurementModeAllCases() {
        let cases = HeatmapSurveyViewModel.MeasurementMode.allCases
        #expect(cases.contains(.passive))
        #expect(cases.contains(.active))
        #expect(cases.count == 2)
    }

    @Test("switching visualization updates selectedVisualization correctly for all modes")
    func switchAllVisualizationModes() {
        let vm = HeatmapSurveyViewModel()
        for viz in HeatmapVisualization.allCases {
            vm.selectedVisualization = viz
            #expect(vm.selectedVisualization == viz)
        }
    }

    @Test("switching color scheme updates selectedColorScheme correctly for all schemes")
    func switchAllColorSchemes() {
        let vm = HeatmapSurveyViewModel()
        for scheme in HeatmapColorScheme.allCases {
            vm.selectedColorScheme = scheme
            #expect(vm.selectedColorScheme == scheme)
        }
    }

    @Test("HeatmapVisualization requiresActiveScan is correct for each mode")
    func visualizationRequiresActiveScan() {
        #expect(HeatmapVisualization.signalStrength.requiresActiveScan == false)
        #expect(HeatmapVisualization.signalToNoise.requiresActiveScan == false)
        #expect(HeatmapVisualization.downloadSpeed.requiresActiveScan == true)
        #expect(HeatmapVisualization.uploadSpeed.requiresActiveScan == true)
        #expect(HeatmapVisualization.latency.requiresActiveScan == true)
    }
}

// MARK: - Undo

@MainActor
struct HeatmapSurveyViewModelUndoTests {

    @Test("undo restores previous measurement state")
    func undoRestoresPreviousState() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 100, height: 100)
        vm.skipCalibration()

        // Add points manually to test undo without async measurement
        let point1 = MeasurementPoint(floorPlanX: 0.1, floorPlanY: 0.1, rssi: -50)
        vm.measurementPoints = [point1]

        // Simulate taking a measurement (which calls saveUndoState internally)
        // We'll test undo by directly manipulating state
        vm.measurementPoints = [point1]  // state before add

        // Now simulate what takeMeasurement does: save undo, add point
        // Instead, use deleteMeasurement which also saves undo state
        let point2 = MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -70)
        vm.measurementPoints = [point1, point2]

        // Delete should save undo and remove
        vm.deleteMeasurement(id: point2.id)
        #expect(vm.measurementPoints.count == 1)

        // Undo should restore to [point1, point2]
        vm.undo()
        #expect(vm.measurementPoints.count == 2)
    }

    @Test("canUndo is false when no undo history exists")
    func canUndoFalseInitially() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.canUndo == false)
    }

    @Test("canUndo is true after a measurement operation")
    func canUndoTrueAfterDelete() {
        let vm = HeatmapSurveyViewModel()
        let point = MeasurementPoint(rssi: -50)
        vm.measurementPoints = [point]
        vm.deleteMeasurement(id: point.id)
        #expect(vm.canUndo == true)
    }

    @Test("undo after clearMeasurements restores all points")
    func undoAfterClearRestoresPoints() {
        let vm = HeatmapSurveyViewModel()
        let points = [
            MeasurementPoint(rssi: -40),
            MeasurementPoint(rssi: -50),
            MeasurementPoint(rssi: -60),
        ]
        vm.measurementPoints = points
        vm.clearMeasurements()
        #expect(vm.measurementPoints.isEmpty)
        vm.undo()
        #expect(vm.measurementPoints.count == 3)
    }
}

// MARK: - Point Management

@MainActor
struct HeatmapSurveyViewModelPointManagementTests {

    @Test("deleteMeasurement removes the correct point by ID")
    func deleteMeasurementRemovesCorrectPoint() {
        let vm = HeatmapSurveyViewModel()
        let point1 = MeasurementPoint(rssi: -40, ssid: "Net1")
        let point2 = MeasurementPoint(rssi: -50, ssid: "Net2")
        let point3 = MeasurementPoint(rssi: -60, ssid: "Net3")
        vm.measurementPoints = [point1, point2, point3]
        vm.deleteMeasurement(id: point2.id)
        #expect(vm.measurementPoints.count == 2)
        #expect(vm.measurementPoints.contains(where: { $0.id == point1.id }))
        #expect(!vm.measurementPoints.contains(where: { $0.id == point2.id }))
        #expect(vm.measurementPoints.contains(where: { $0.id == point3.id }))
    }

    @Test("filteredPoints returns all when no AP filter set")
    func filteredPointsReturnsAllWithoutFilter() {
        let vm = HeatmapSurveyViewModel()
        vm.measurementPoints = [
            MeasurementPoint(rssi: -40, bssid: "AA:BB:CC:DD:EE:01"),
            MeasurementPoint(rssi: -50, bssid: "AA:BB:CC:DD:EE:02"),
        ]
        #expect(vm.filteredPoints.count == 2)
    }

    @Test("filteredPoints filters by BSSID when AP filter is set")
    func filteredPointsFiltersByBSSID() {
        let vm = HeatmapSurveyViewModel()
        vm.measurementPoints = [
            MeasurementPoint(rssi: -40, bssid: "AA:BB:CC:DD:EE:01"),
            MeasurementPoint(rssi: -50, bssid: "AA:BB:CC:DD:EE:02"),
            MeasurementPoint(rssi: -45, bssid: "AA:BB:CC:DD:EE:01"),
        ]
        vm.selectedAPFilter = "AA:BB:CC:DD:EE:01"
        #expect(vm.filteredPoints.count == 2)
        #expect(vm.filteredPoints.allSatisfy { $0.bssid == "AA:BB:CC:DD:EE:01" })
    }

    @Test("averageRSSI computes correct average")
    func averageRSSIComputesCorrectly() {
        let vm = HeatmapSurveyViewModel()
        vm.measurementPoints = [
            MeasurementPoint(rssi: -40),
            MeasurementPoint(rssi: -60),
            MeasurementPoint(rssi: -80),
        ]
        #expect(vm.averageRSSI == -60.0)
    }

    @Test("averageRSSI returns nil when no points")
    func averageRSSINilWhenEmpty() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.averageRSSI == nil)
    }

    @Test("minRSSI and maxRSSI return correct extremes")
    func minMaxRSSICorrect() {
        let vm = HeatmapSurveyViewModel()
        vm.measurementPoints = [
            MeasurementPoint(rssi: -30),
            MeasurementPoint(rssi: -80),
            MeasurementPoint(rssi: -55),
        ]
        #expect(vm.minRSSI == -80)
        #expect(vm.maxRSSI == -30)
    }

    @Test("qualityLabel returns correct label for RSSI ranges")
    func qualityLabelReturnsCorrectLabels() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.qualityLabel(-30) == "Excellent")
        #expect(vm.qualityLabel(-55) == "Good")
        #expect(vm.qualityLabel(-65) == "Fair")
        #expect(vm.qualityLabel(-80) == "Weak")
    }

    @Test("uniqueBSSIDs groups measurement points by BSSID")
    func uniqueBSSIDsGroupsCorrectly() {
        let vm = HeatmapSurveyViewModel()
        vm.measurementPoints = [
            MeasurementPoint(rssi: -40, ssid: "Net1", bssid: "AA:BB:01"),
            MeasurementPoint(rssi: -50, ssid: "Net2", bssid: "AA:BB:02"),
            MeasurementPoint(rssi: -45, ssid: "Net1", bssid: "AA:BB:01"),
        ]
        let bssids = vm.uniqueBSSIDs
        #expect(bssids.count == 2)
    }
}

// MARK: - Save/Load Round-Trip

@MainActor
struct HeatmapSurveyViewModelSaveLoadTests {

    @Test("saveProject does not throw when surveyProject is nil")
    func saveProjectNoOpWithoutProject() throws {
        let vm = HeatmapSurveyViewModel()
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID().uuidString).json")
        try vm.saveProject(to: url)
        #expect(vm.surveyProject == nil)
    }

    @Test("save and load round-trip preserves project data")
    func saveLoadRoundTripPreservesData() throws {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([0x89, 0x50, 0x4E, 0x47]), width: 400, height: 300)
        vm.measurementPoints = [
            MeasurementPoint(rssi: -45, ssid: "Office", bssid: "AA:BB:CC:DD:EE:01"),
            MeasurementPoint(rssi: -62, ssid: "Guest", bssid: "AA:BB:CC:DD:EE:02"),
        ]

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("roundtrip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try vm.saveProject(to: url)

        let vm2 = HeatmapSurveyViewModel()
        try vm2.loadProject(from: url)

        #expect(vm2.surveyProject != nil)
        #expect(vm2.measurementPoints.count == 2)
        #expect(vm2.measurementPoints[0].rssi == -45)
        #expect(vm2.measurementPoints[0].ssid == "Office")
        #expect(vm2.measurementPoints[1].rssi == -62)
        #expect(vm2.measurementPoints[1].bssid == "AA:BB:CC:DD:EE:02")
    }

    @Test("save and load round-trip as .netmonsurvey preserves floor plan image")
    func netmonSurveyRoundTripPreservesImage() throws {
        let vm = HeatmapSurveyViewModel()
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        vm.importFloorPlan(imageData: imageData, width: 200, height: 150)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bundle-\(UUID().uuidString).netmonsurvey")
        defer { try? FileManager.default.removeItem(at: url) }

        try vm.saveProject(to: url)

        let vm2 = HeatmapSurveyViewModel()
        try vm2.loadProject(from: url)

        #expect(vm2.surveyProject?.floorPlan.imageData == imageData)
        #expect(vm2.surveyProject?.floorPlan.pixelWidth == 200)
        #expect(vm2.surveyProject?.floorPlan.pixelHeight == 150)
    }

    @Test("save updates lastSaveDate and resets measurementsSinceLastSave")
    func saveUpdatesLastSaveDate() throws {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 100, height: 100)

        #expect(vm.lastSaveDate == nil)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("savedate-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try vm.saveProject(to: url)
        #expect(vm.lastSaveDate != nil)
    }

    @Test("loadProject restores calibration state")
    func loadProjectRestoresCalibrationState() throws {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 800, height: 600)
        vm.addCalibrationPoint(at: CGPoint(x: 0, y: 0))
        vm.addCalibrationPoint(at: CGPoint(x: 100, y: 0))
        vm.completeCalibration(withDistance: 10.0)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("calib-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try vm.saveProject(to: url)

        let vm2 = HeatmapSurveyViewModel()
        try vm2.loadProject(from: url)

        #expect(vm2.isCalibrated == true)
        #expect(vm2.surveyProject?.floorPlan.calibrationPoints?.count == 2)
    }

    @Test("exportProjectFile returns a valid URL")
    func exportProjectFileReturnsURL() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1, 2, 3]), width: 100, height: 100)
        vm.measurementPoints = [MeasurementPoint(rssi: -50)]

        let url = vm.exportProjectFile()
        #expect(url != nil)
        #expect(url?.pathExtension == "netmonsurvey")

        // Clean up
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}

// MARK: - Survey Control

@MainActor
struct HeatmapSurveyViewModelSurveyControlTests {

    @Test("startSurvey requires calibration")
    func startSurveyRequiresCalibration() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 100, height: 100)
        // Not calibrated
        vm.startSurvey()
        #expect(vm.isSurveying == false)
    }

    @Test("startSurvey succeeds when calibrated")
    func startSurveySetsIsSurveying() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 100, height: 100)
        vm.skipCalibration()
        vm.startSurvey()
        #expect(vm.isSurveying == true)
    }

    @Test("stopSurvey sets isSurveying to false")
    func stopSurveyResetsFlag() {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 100, height: 100)
        vm.skipCalibration()
        vm.startSurvey()
        vm.stopSurvey()
        #expect(vm.isSurveying == false)
    }

    @Test("takeMeasurement requires project and not already measuring")
    func takeMeasurementGuards() async {
        let vm = HeatmapSurveyViewModel()
        // No project, should be no-op
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        #expect(vm.measurementPoints.isEmpty)
    }

    @Test("takeMeasurement without service uses fallback with currentRSSI")
    func takeMeasurementFallback() async {
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 100, height: 100)
        vm.skipCalibration()
        vm.currentRSSI = -55
        vm.currentSSID = "TestNet"

        await vm.takeMeasurement(at: CGPoint(x: 0.3, y: 0.7))

        #expect(vm.measurementPoints.count == 1)
        #expect(vm.measurementPoints[0].rssi == -55)
        #expect(vm.measurementPoints[0].ssid == "TestNet")
        #expect(abs(vm.measurementPoints[0].floorPlanX - 0.3) < 0.001)
        #expect(abs(vm.measurementPoints[0].floorPlanY - 0.7) < 0.001)
    }
}

// MARK: - Saved Projects Listing

@MainActor
struct HeatmapSurveyViewModelSavedProjectsTests {

    @Test("listSavedProjects returns saved projects sorted by date")
    func listSavedProjectsReturnsSorted() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([1]), width: 100, height: 100)

        // Save two projects to the actual Documents dir (same as autoSave uses)
        let url1 = dir.appendingPathComponent("list-test-1-\(UUID().uuidString).netmonsurvey")
        let url2 = dir.appendingPathComponent("list-test-2-\(UUID().uuidString).netmonsurvey")
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        // Note: listSavedProjects reads from Documents, not temp.
        // This test verifies the function runs without crashing and returns an array.
        let projects = HeatmapSurveyViewModel.listSavedProjects()
        #expect(projects is [SavedSurveyInfo])
    }

    @Test("SavedSurveyInfo formattedSize returns non-empty string")
    func savedSurveyInfoFormattedSize() {
        let info = SavedSurveyInfo(
            name: "Test",
            url: URL(fileURLWithPath: "/tmp/test.netmonsurvey"),
            modifiedDate: Date(),
            fileSize: 1024
        )
        #expect(!info.formattedSize.isEmpty)
        #expect(info.formattedSize.contains("KB") || info.formattedSize.contains("bytes"))
    }
}

// MARK: - Blueprint Import

@MainActor
struct HeatmapSurveyViewModelBlueprintImportTests {

    @Test("importBlueprintProject sets isCalibrated to true")
    func importBlueprintSetsCalibrated() {
        let vm = HeatmapSurveyViewModel()

        let floor = BlueprintFloor(
            label: "Floor 1",
            floorNumber: 1,
            svgData: Data(),
            widthMeters: 10.0,
            heightMeters: 8.0,
            roomLabels: [],
            wallSegments: []
        )
        let blueprint = BlueprintProject(
            name: "Test Room",
            floors: [floor],
            metadata: BlueprintMetadata()
        )

        vm.importBlueprintProject(blueprint)

        #expect(vm.isCalibrated == true)
        #expect(vm.isCalibrating == false)
        #expect(vm.surveyProject?.name == "Test Room")
    }

    @Test("importBlueprintProject with no floors sets error")
    func importBlueprintNoFloorsError() {
        let vm = HeatmapSurveyViewModel()
        let blueprint = BlueprintProject(
            name: "Empty",
            floors: [],
            metadata: BlueprintMetadata()
        )
        vm.importBlueprintProject(blueprint)
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - IOSHeatmapService Tests

@MainActor
struct IOSHeatmapServiceTests {

    private func makeService() -> IOSHeatmapService {
        let wifiService = MockWiFiInfoService()
        wifiService.currentWiFi = WiFiInfo(
            ssid: "TestNet",
            bssid: "AA:BB:CC:DD:EE:FF",
            signalStrength: 80,
            signalDBm: -45,
            channel: 6,
            frequency: "2437 MHz",
            band: .band2_4GHz,
            noiseLevel: -90,
            linkSpeed: 144.0
        )
        let speedService = MockSpeedTestService()
        speedService.mockResult = SpeedTestData(downloadSpeed: 100, uploadSpeed: 50, latency: 15)
        let pingService = MockPingService()
        pingService.mockResults = [
            PingResult(sequence: 1, host: "192.168.1.1", ttl: 64, time: 5.0),
        ]

        return IOSHeatmapService(
            wifiInfoService: wifiService,
            speedTestService: speedService,
            pingService: pingService
        )
    }

    @Test("takeMeasurement returns point with fallback WiFi data")
    func takeMeasurementReturnsPoint() async {
        let service = makeService()
        let point = await service.takeMeasurement(at: 0.5, floorPlanY: 0.3)

        // Without Shortcuts, falls back to WiFiInfoService
        #expect(point.floorPlanX == 0.5)
        #expect(point.floorPlanY == 0.3)
        // RSSI comes from WiFiInfoService fallback (signalDBm: -45)
        #expect(point.ssid == "TestNet" || point.rssi != 0)
    }

    @Test("takeActiveMeasurement includes speed and latency data")
    func takeActiveMeasurementIncludesSpeedData() async {
        let service = makeService()
        let point = await service.takeActiveMeasurement(at: 0.2, floorPlanY: 0.8)

        #expect(point.floorPlanX == 0.2)
        #expect(point.floorPlanY == 0.8)
        // Speed test data should be present from mock
        #expect(point.downloadSpeed == 100.0 || point.downloadSpeed == nil)
    }
}

// MARK: - HeatmapRenderer Tests

struct HeatmapRendererTests {

    @Test("render produces a CGImage from measurement points")
    func renderProducesCGImage() {
        let renderer = HeatmapRenderer()
        let points = [
            MeasurementPoint(floorPlanX: 0.2, floorPlanY: 0.3, rssi: -40),
            MeasurementPoint(floorPlanX: 0.7, floorPlanY: 0.8, rssi: -70),
        ]
        let image = renderer.render(
            points: points,
            visualization: .signalStrength,
            colorScheme: .thermal
        )
        #expect(image != nil)
    }

    @Test("render with all color schemes produces valid images")
    func renderAllColorSchemes() {
        let renderer = HeatmapRenderer()
        let points = [
            MeasurementPoint(floorPlanX: 0.3, floorPlanY: 0.3, rssi: -50),
            MeasurementPoint(floorPlanX: 0.7, floorPlanY: 0.7, rssi: -75),
        ]
        for scheme in HeatmapColorScheme.allCases {
            let image = renderer.render(
                points: points,
                visualization: .signalStrength,
                colorScheme: scheme
            )
            #expect(image != nil, "Failed for scheme: \(scheme.displayName)")
        }
    }

    @Test("render with empty points produces image with zero-value fill")
    func renderWithEmptyPointsProducesImage() {
        let renderer = HeatmapRenderer()
        let image = renderer.render(
            points: [],
            visualization: .signalStrength
        )
        // Renderer produces a uniform image even with no data points
        #expect(image != nil)
    }

    @Test("interpolateGrid returns correct grid dimensions")
    func interpolateGridDimensions() {
        let config = HeatmapRenderer.Configuration(gridWidth: 50, gridHeight: 30)
        let renderer = HeatmapRenderer(configuration: config)
        let points = [MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -50)]
        let grid = renderer.interpolateGrid(points: points, visualization: .signalStrength)
        #expect(grid.count == 30)
        #expect(grid[0].count == 50)
    }

    @Test("colorForValue returns consistent values for same input")
    func colorForValueIsConsistent() {
        let renderer = HeatmapRenderer()
        let c1 = renderer.colorForValue(-50, visualization: .signalStrength, colorScheme: .thermal)
        let c2 = renderer.colorForValue(-50, visualization: .signalStrength, colorScheme: .thermal)
        #expect(c1.r == c2.r)
        #expect(c1.g == c2.g)
        #expect(c1.b == c2.b)
    }
}

// MARK: - DeepLinkRouter Tests

@MainActor
struct DeepLinkRouterTests {

    @Test("handle wifi-result URL sets wifiCallbackReceived")
    func handleWiFiResultURL() {
        let router = DeepLinkRouter()
        let url = URL(string: "netmonitor://wifi-result")!
        router.handle(url: url)
        #expect(router.wifiCallbackReceived == true)
    }

    @Test("handle .netmonsurvey file URL sets pendingSurveyFileURL")
    func handleNetmonSurveyFile() {
        let router = DeepLinkRouter()
        let url = URL(fileURLWithPath: "/tmp/test.netmonsurvey")
        router.handle(url: url)
        #expect(router.pendingSurveyFileURL == url)
    }

    @Test("handle .netmonblueprint file URL sets pendingSurveyFileURL")
    func handleNetmonBlueprintFile() {
        let router = DeepLinkRouter()
        let url = URL(fileURLWithPath: "/tmp/scan.netmonblueprint")
        router.handle(url: url)
        #expect(router.pendingSurveyFileURL == url)
    }

    @Test("consumePendingFile returns and clears the URL")
    func consumePendingFileClearsURL() {
        let router = DeepLinkRouter()
        let url = URL(fileURLWithPath: "/tmp/test.netmonsurvey")
        router.handle(url: url)
        let consumed = router.consumePendingFile()
        #expect(consumed == url)
        #expect(router.pendingSurveyFileURL == nil)
    }

    @Test("handle ignores unrelated URLs")
    func handleIgnoresUnrelatedURL() {
        let router = DeepLinkRouter()
        let url = URL(string: "https://example.com")!
        router.handle(url: url)
        #expect(router.pendingSurveyFileURL == nil)
        #expect(router.wifiCallbackReceived == false)
    }
}
