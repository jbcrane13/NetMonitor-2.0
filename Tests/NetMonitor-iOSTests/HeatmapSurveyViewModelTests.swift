import Foundation
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - HeatmapSurveyViewModel Tests

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

        // Two points: (0,0) and (100,0) in pixel space → 100px apart
        // knownDistance = 10m → metersPerPixel = 10/100 = 0.1
        vm.addCalibrationPoint(at: CGPoint(x: 0.0, y: 0.0))
        vm.addCalibrationPoint(at: CGPoint(x: 100.0, y: 0.0))
        vm.completeCalibration(withDistance: 10.0)

        // widthMeters = 1000 * 0.1 = 100, heightMeters = 500 * 0.1 = 50
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
        // should not crash, project remains nil
        vm.completeCalibration(withDistance: 5.0)
        #expect(vm.surveyProject == nil)
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
}

// MARK: - Save/Load

@MainActor
struct HeatmapSurveyViewModelSaveLoadTests {

    @Test("saveProject does not throw when surveyProject is nil")
    func saveProjectNoOpWithoutProject() throws {
        let vm = HeatmapSurveyViewModel()
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-\(UUID().uuidString).json")
        // Should return without error when project is nil
        try vm.saveProject(to: url)
        #expect(vm.surveyProject == nil)
    }

    @Test("loadProject sets surveyProject and measurementPoints")
    func loadProjectSetsSurveyProject() throws {
        // Create a project, save it, then load it back
        let vm = HeatmapSurveyViewModel()
        vm.importFloorPlan(imageData: Data([0x89, 0x50, 0x4E, 0x47]), width: 400, height: 300)
        vm.measurementPoints = [MeasurementPoint(rssi: -45, ssid: "Office")]

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("load-test-\(UUID().uuidString).json")
        try vm.saveProject(to: url)

        let vm2 = HeatmapSurveyViewModel()
        try vm2.loadProject(from: url)

        #expect(vm2.surveyProject != nil)
        #expect(vm2.measurementPoints.count == 1)
        #expect(vm2.measurementPoints.first?.rssi == -45)
        #expect(vm2.measurementPoints.first?.ssid == "Office")
    }
}
