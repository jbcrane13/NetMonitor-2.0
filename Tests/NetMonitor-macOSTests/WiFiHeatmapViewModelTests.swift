import Foundation
import Testing
@testable import NetMonitor_macOS
import NetMonitorCore

// MARK: - WiFiHeatmapViewModel init state tests

@MainActor
struct WiFiHeatmapViewModelInitTests {

    @Test("surveyProject is nil on init")
    func surveyProjectNil() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.surveyProject == nil)
    }

    @Test("measurementPoints is empty on init")
    func measurementPointsEmpty() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.measurementPoints.isEmpty)
    }

    @Test("isSurveying is false on init")
    func isSurveyingFalse() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.isSurveying == false)
    }

    @Test("isMeasuring is false on init")
    func isMeasuringFalse() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.isMeasuring == false)
    }

    @Test("isCalibrating is false on init")
    func isCalibratingFalse() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.isCalibrating == false)
    }

    @Test("isCalibrated is false on init")
    func isCalibratedFalse() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.isCalibrated == false)
    }

    @Test("heatmapCGImage is nil on init")
    func heatmapCGImageNil() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.heatmapCGImage == nil)
    }

    @Test("isHeatmapGenerated is false on init")
    func isHeatmapGeneratedFalse() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.isHeatmapGenerated == false)
    }

    @Test("sidebarMode defaults to survey")
    func sidebarModeDefaultsSurvey() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.sidebarMode == .survey)
    }

    @Test("overlayOpacity defaults to 0.7")
    func overlayOpacityDefault() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.overlayOpacity == 0.7)
    }

    @Test("coverageThreshold defaults to -70")
    func coverageThresholdDefault() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.coverageThreshold == -70)
    }

    @Test("selectedAPFilter is nil on init")
    func selectedAPFilterNil() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.selectedAPFilter == nil)
    }

    @Test("canUndo is false on init")
    func canUndoFalse() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.canUndo == false)
    }
}

// MARK: - Calibration flow tests

@MainActor
struct WiFiHeatmapViewModelCalibrationTests {

    @Test("startCalibration sets isCalibrating true and isCalibrated false")
    func startCalibration() {
        let vm = WiFiHeatmapViewModel()
        vm.startCalibration()
        #expect(vm.isCalibrating == true)
        #expect(vm.isCalibrated == false)
        #expect(vm.calibrationPoints.isEmpty)
    }

    @Test("cancelCalibration resets isCalibrating and calibrationPoints")
    func cancelCalibration() {
        let vm = WiFiHeatmapViewModel()
        vm.startCalibration()
        vm.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.2))
        vm.cancelCalibration()
        #expect(vm.isCalibrating == false)
        #expect(vm.calibrationPoints.isEmpty)
    }

    @Test("addCalibrationPoint appends up to 2 points")
    func addCalibrationPointsUpToTwo() {
        let vm = WiFiHeatmapViewModel()
        vm.startCalibration()
        vm.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.2))
        #expect(vm.calibrationPoints.count == 1)
        vm.addCalibrationPoint(at: CGPoint(x: 0.8, y: 0.9))
        #expect(vm.calibrationPoints.count == 2)
    }

    @Test("addCalibrationPoint ignores third point")
    func addCalibrationPointIgnoresThird() {
        let vm = WiFiHeatmapViewModel()
        vm.startCalibration()
        vm.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.2))
        vm.addCalibrationPoint(at: CGPoint(x: 0.8, y: 0.9))
        vm.addCalibrationPoint(at: CGPoint(x: 0.5, y: 0.5))
        #expect(vm.calibrationPoints.count == 2)
    }

    @Test("second calibration point shows calibration sheet")
    func secondPointShowsSheet() {
        let vm = WiFiHeatmapViewModel()
        vm.startCalibration()
        vm.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.2))
        #expect(vm.showCalibrationSheet == false)
        vm.addCalibrationPoint(at: CGPoint(x: 0.8, y: 0.9))
        #expect(vm.showCalibrationSheet == true)
    }

    @Test("completeCalibration sets isCalibrated and clears isCalibrating")
    func completeCalibration() throws {
        let vm = WiFiHeatmapViewModel()
        let pngData = makeTestPNGData()
        try vm.importFloorPlan(imageData: pngData, name: "Test")
        // importFloorPlan starts calibration automatically
        #expect(vm.isCalibrating == true)
        vm.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.2))
        vm.addCalibrationPoint(at: CGPoint(x: 0.8, y: 0.9))
        vm.completeCalibration(withDistance: 5.0)
        #expect(vm.isCalibrated == true)
        #expect(vm.isCalibrating == false)
        #expect(vm.calibrationPoints.isEmpty)
        #expect(vm.showCalibrationSheet == false)
    }
}

// MARK: - Survey control tests

@MainActor
struct WiFiHeatmapViewModelSurveyTests {

    private func makeCalibrated() throws -> WiFiHeatmapViewModel {
        let vm = WiFiHeatmapViewModel()
        let pngData = makeTestPNGData()
        try vm.importFloorPlan(imageData: pngData, name: "Test Floor")
        vm.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.2))
        vm.addCalibrationPoint(at: CGPoint(x: 0.8, y: 0.9))
        vm.completeCalibration(withDistance: 5.0)
        return vm
    }

    @Test("startSurvey requires surveyProject and isCalibrated")
    func startSurveyRequiresProjectAndCalibration() {
        let vm = WiFiHeatmapViewModel()
        vm.startSurvey()
        #expect(vm.isSurveying == false)
    }

    @Test("startSurvey sets isSurveying true when project and calibration present")
    func startSurveySuccess() throws {
        let vm = try makeCalibrated()
        vm.startSurvey()
        #expect(vm.isSurveying == true)
    }

    @Test("startSurvey sets sidebarMode to survey")
    func startSurveySetsSidebarMode() throws {
        let vm = try makeCalibrated()
        vm.sidebarMode = .analyze
        vm.startSurvey()
        #expect(vm.sidebarMode == .survey)
    }

    @Test("startSurvey clears previous heatmap state")
    func startSurveyClearsHeatmap() throws {
        let vm = try makeCalibrated()
        vm.isHeatmapGenerated = true
        vm.startSurvey()
        #expect(vm.isHeatmapGenerated == false)
        #expect(vm.heatmapCGImage == nil)
    }

    @Test("stopSurvey sets isSurveying false")
    func stopSurvey() throws {
        let vm = try makeCalibrated()
        vm.startSurvey()
        vm.stopSurvey()
        #expect(vm.isSurveying == false)
    }
}

// MARK: - Point management tests

@MainActor
struct WiFiHeatmapViewModelPointTests {

    @Test("deletePoint removes the specified point")
    func deletePoint() {
        let vm = WiFiHeatmapViewModel()
        let point = MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60)
        vm.measurementPoints = [point]
        vm.deletePoint(id: point.id)
        #expect(vm.measurementPoints.isEmpty)
    }

    @Test("deletePoint saves undo state")
    func deletePointSavesUndo() {
        let vm = WiFiHeatmapViewModel()
        let point = MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60)
        vm.measurementPoints = [point]
        vm.deletePoint(id: point.id)
        #expect(vm.canUndo == true)
    }

    @Test("clearMeasurements removes all points and clears heatmap")
    func clearMeasurements() {
        let vm = WiFiHeatmapViewModel()
        vm.measurementPoints = [
            MeasurementPoint(floorPlanX: 0.1, floorPlanY: 0.1, rssi: -50),
            MeasurementPoint(floorPlanX: 0.9, floorPlanY: 0.9, rssi: -70),
        ]
        vm.isHeatmapGenerated = true
        vm.clearMeasurements()
        #expect(vm.measurementPoints.isEmpty)
        #expect(vm.isHeatmapGenerated == false)
        #expect(vm.heatmapCGImage == nil)
    }

    @Test("clearMeasurements saves undo state")
    func clearMeasurementsSavesUndo() {
        let vm = WiFiHeatmapViewModel()
        vm.measurementPoints = [
            MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60),
        ]
        vm.clearMeasurements()
        #expect(vm.canUndo == true)
    }

    @Test("undo restores previous measurement points")
    func undoRestoresPoints() {
        let vm = WiFiHeatmapViewModel()
        let point = MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60)
        vm.measurementPoints = [point]
        vm.clearMeasurements()
        #expect(vm.measurementPoints.isEmpty)
        vm.undo()
        #expect(vm.measurementPoints.count == 1)
        #expect(vm.measurementPoints.first?.id == point.id)
    }

    @Test("undo on empty stack does nothing")
    func undoEmptyStack() {
        let vm = WiFiHeatmapViewModel()
        vm.undo()
        #expect(vm.measurementPoints.isEmpty)
    }
}

// MARK: - Computed property tests

@MainActor
struct WiFiHeatmapViewModelComputedTests {

    @Test("averageRSSI returns nil when no points")
    func averageRSSINilWhenEmpty() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.averageRSSI == nil)
    }

    @Test("averageRSSI computes correct average")
    func averageRSSIComputes() {
        let vm = WiFiHeatmapViewModel()
        vm.measurementPoints = [
            MeasurementPoint(floorPlanX: 0.1, floorPlanY: 0.1, rssi: -40),
            MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60),
            MeasurementPoint(floorPlanX: 0.9, floorPlanY: 0.9, rssi: -80),
        ]
        #expect(vm.averageRSSI == -60.0)
    }

    @Test("minRSSI returns the weakest signal")
    func minRSSI() {
        let vm = WiFiHeatmapViewModel()
        vm.measurementPoints = [
            MeasurementPoint(floorPlanX: 0.1, floorPlanY: 0.1, rssi: -40),
            MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -80),
        ]
        #expect(vm.minRSSI == -80)
    }

    @Test("maxRSSI returns the strongest signal")
    func maxRSSI() {
        let vm = WiFiHeatmapViewModel()
        vm.measurementPoints = [
            MeasurementPoint(floorPlanX: 0.1, floorPlanY: 0.1, rssi: -40),
            MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -80),
        ]
        #expect(vm.maxRSSI == -40)
    }

    @Test("minRSSI and maxRSSI return nil when no points")
    func minMaxRSSINilWhenEmpty() {
        let vm = WiFiHeatmapViewModel()
        #expect(vm.minRSSI == nil)
        #expect(vm.maxRSSI == nil)
    }

    @Test("filteredPoints returns all when no AP filter")
    func filteredPointsNoFilter() {
        let vm = WiFiHeatmapViewModel()
        vm.measurementPoints = [
            MeasurementPoint(floorPlanX: 0.1, floorPlanY: 0.1, rssi: -50),
            MeasurementPoint(floorPlanX: 0.9, floorPlanY: 0.9, rssi: -70),
        ]
        #expect(vm.filteredPoints.count == 2)
    }

    @Test("filteredPoints respects AP filter by BSSID")
    func filteredPointsWithAPFilter() {
        let vm = WiFiHeatmapViewModel()
        vm.measurementPoints = [
            MeasurementPoint(floorPlanX: 0.1, floorPlanY: 0.1, rssi: -50, bssid: "AA:BB:CC:DD:EE:01"),
            MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60, bssid: "AA:BB:CC:DD:EE:02"),
            MeasurementPoint(floorPlanX: 0.9, floorPlanY: 0.9, rssi: -70, bssid: "AA:BB:CC:DD:EE:01"),
        ]
        vm.selectedAPFilter = "AA:BB:CC:DD:EE:01"
        #expect(vm.filteredPoints.count == 2)
    }

    @Test("uniqueBSSIDs extracts distinct BSSIDs sorted by SSID")
    func uniqueBSSIDs() {
        let vm = WiFiHeatmapViewModel()
        vm.measurementPoints = [
            MeasurementPoint(floorPlanX: 0.1, floorPlanY: 0.1, rssi: -50, ssid: "Network-B", bssid: "BB:BB"),
            MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60, ssid: "Network-A", bssid: "AA:AA"),
            MeasurementPoint(floorPlanX: 0.9, floorPlanY: 0.9, rssi: -70, ssid: "Network-B", bssid: "BB:BB"),
        ]
        let bssids = vm.uniqueBSSIDs
        #expect(bssids.count == 2)
        #expect(bssids.first?.ssid == "Network-A")
        #expect(bssids.last?.ssid == "Network-B")
    }
}

// MARK: - Floor plan import tests

@MainActor
struct WiFiHeatmapViewModelImportTests {

    @Test("importFloorPlan from URL creates survey project")
    func importFromURL() throws {
        let vm = WiFiHeatmapViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.importFloorPlan(from: url)
        #expect(vm.surveyProject != nil)
    }

    @Test("importFloorPlan from URL derives project name from filename")
    func importDeriveProjectName() throws {
        let vm = WiFiHeatmapViewModel()
        let url = makeTestPNGFile(name: "Office_Floor2.png")
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.importFloorPlan(from: url)
        #expect(vm.surveyProject?.name == "Office_Floor2")
    }

    @Test("importFloorPlan from imageData creates survey project with given name")
    func importFromImageData() throws {
        let vm = WiFiHeatmapViewModel()
        let data = makeTestPNGData()
        try vm.importFloorPlan(imageData: data, name: "Custom Name")
        #expect(vm.surveyProject?.name == "Custom Name")
    }

    @Test("importFloorPlan starts calibration")
    func importStartsCalibration() throws {
        let vm = WiFiHeatmapViewModel()
        let data = makeTestPNGData()
        try vm.importFloorPlan(imageData: data, name: "Test")
        #expect(vm.isCalibrating == true)
        #expect(vm.isCalibrated == false)
    }

    @Test("importFloorPlan clears previous measurement state")
    func importClearsPreviousState() throws {
        let vm = WiFiHeatmapViewModel()
        vm.measurementPoints = [MeasurementPoint(floorPlanX: 0.5, floorPlanY: 0.5, rssi: -60)]
        vm.isHeatmapGenerated = true
        let data = makeTestPNGData()
        try vm.importFloorPlan(imageData: data, name: "New")
        #expect(vm.measurementPoints.isEmpty)
        #expect(vm.isHeatmapGenerated == false)
        #expect(vm.heatmapCGImage == nil)
    }

    @Test("importFloorPlan with invalid data throws invalidImage error")
    func importInvalidDataThrows() {
        let vm = WiFiHeatmapViewModel()
        #expect(throws: HeatmapError.invalidImage) {
            try vm.importFloorPlan(imageData: Data([0x00, 0x01, 0x02]), name: "Bad")
        }
    }
}

// MARK: - HeatmapError tests

struct HeatmapErrorTests {

    @Test("invalidImage has descriptive error message")
    func invalidImageDescription() {
        #expect(HeatmapError.invalidImage.errorDescription == "Invalid image format")
    }

    @Test("noFloorPlan has descriptive error message")
    func noFloorPlanDescription() {
        #expect(HeatmapError.noFloorPlan.errorDescription == "No floor plan loaded")
    }

    @Test("saveFailed has descriptive error message")
    func saveFailedDescription() {
        #expect(HeatmapError.saveFailed.errorDescription == "Failed to save project")
    }
}
