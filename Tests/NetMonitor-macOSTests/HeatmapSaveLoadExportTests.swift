import AppKit
import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

// MARK: - Save / Load / Export Tests

@Suite("HeatmapSurveyViewModel — Save, Load, Export & New Project")
@MainActor
struct HeatmapSaveLoadExportTests {

    // MARK: - Factory

    private func makeVMWithFloorPlan() -> (HeatmapSurveyViewModel, MockMeasurementEngine) {
        let engine = MockMeasurementEngine()
        let wlanService = MockCoreWLANService()
        let vm = HeatmapSurveyViewModel(measurementEngine: engine, coreWLANService: wlanService)
        let url = makeTestPNGFile(width: 200, height: 150)
        vm.loadFloorPlan(from: url)
        return (vm, engine)
    }

    // MARK: - Save / Overwrite

    @Test func savePathInitiallyNil() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.currentSavePath == nil)
    }

    @Test func loadProjectSetsSavePath() throws {
        let (vm, _) = makeVMWithFloorPlan()
        guard let project = vm.project else {
            Issue.record("Expected project")
            return
        }

        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("save_path_test.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try SurveyFileManager.save(project, to: bundleURL)

        vm.loadProject(from: bundleURL)
        #expect(vm.currentSavePath == bundleURL)
    }

    @Test func overwriteExistingPathPreservesData() async throws {
        let (vm, engine) = makeVMWithFloorPlan()

        // Save initial project
        guard let project = vm.project else {
            Issue.record("Expected project")
            return
        }
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("overwrite_test.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try SurveyFileManager.save(project, to: bundleURL)
        vm.loadProject(from: bundleURL)

        // Add measurement points
        await vm.takeMeasurement(at: CGPoint(x: 0.3, y: 0.3))
        await vm.takeMeasurement(at: CGPoint(x: 0.6, y: 0.6))

        // Save (should overwrite since currentSavePath is set)
        // We can't test NSSavePanel in unit tests, but we can verify the path is set
        #expect(vm.currentSavePath == bundleURL)
        #expect(vm.project?.measurementPoints.count == 2)
    }

    // MARK: - Load Restores Full State

    @Test func loadProjectRestoresFloorPlan() throws {
        let (vm, _) = makeVMWithFloorPlan()
        guard let project = vm.project else {
            Issue.record("Expected project")
            return
        }
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("load_fp_test.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try SurveyFileManager.save(project, to: bundleURL)

        let vm2 = HeatmapSurveyViewModel()
        vm2.loadProject(from: bundleURL)

        #expect(vm2.hasFloorPlan == true)
        #expect(vm2.floorPlanImage != nil)
        #expect(vm2.importResult != nil)
        #expect(vm2.project != nil)
    }

    @Test func loadProjectRestoresMeasurementPoints() async throws {
        let (vm, engine) = makeVMWithFloorPlan()

        engine.setMockRSSI(-45)
        await vm.takeMeasurement(at: CGPoint(x: 0.2, y: 0.3))
        engine.setMockRSSI(-65)
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        engine.setMockRSSI(-80)
        await vm.takeMeasurement(at: CGPoint(x: 0.8, y: 0.7))

        guard let project = vm.project else {
            Issue.record("Expected project")
            return
        }
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("load_pts_test.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try SurveyFileManager.save(project, to: bundleURL)

        let vm2 = HeatmapSurveyViewModel()
        vm2.loadProject(from: bundleURL)

        #expect(vm2.project?.measurementPoints.count == 3)
        #expect(vm2.summaryStats.count == 3)
    }

    @Test func loadProjectRestoresHeatmapOverlay() async throws {
        let (vm, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))
        #expect(vm.heatmapOverlayImage != nil)

        guard let project = vm.project else {
            Issue.record("Expected project")
            return
        }
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("load_overlay_test.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try SurveyFileManager.save(project, to: bundleURL)

        let vm2 = HeatmapSurveyViewModel()
        vm2.loadProject(from: bundleURL)

        // After loading 3+ points, overlay should be rendered
        #expect(vm2.heatmapOverlayImage != nil)
        #expect(vm2.summaryStats.count == 3)
    }

    @Test func loadProjectRestoresCalibration() throws {
        let (vm, _) = makeVMWithFloorPlan()

        // Calibrate using full-width points
        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters
        vm.applyCalibration()
        #expect(vm.isCalibrated == true)

        guard let project = vm.project else {
            Issue.record("Expected project")
            return
        }
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("load_calib_test.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try SurveyFileManager.save(project, to: bundleURL)

        let vm2 = HeatmapSurveyViewModel()
        vm2.loadProject(from: bundleURL)

        #expect(vm2.isCalibrated == true)
        #expect(vm2.pixelsPerMeter > 0)
        #expect(vm2.scaleBarLabel.isEmpty == false)
    }

    // MARK: - PDF Export

    @Test func canExportPDFRequires3Points() async {
        let (vm, _) = makeVMWithFloorPlan()

        // 0 points
        #expect(vm.canExportPDF == false)

        // 1 point
        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        #expect(vm.canExportPDF == false)

        // 2 points
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        #expect(vm.canExportPDF == false)

        // 3 points
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))
        #expect(vm.canExportPDF == true)
    }

    @Test func canExportPDFFalseWithNoProject() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.canExportPDF == false)
    }

    @Test func pdfExporterGenerates3PagePDF() async throws {
        let (vm, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))

        guard let project = vm.project, let floorPlanImage = vm.floorPlanImage else {
            Issue.record("Expected project and floor plan image")
            return
        }

        let pdfData = HeatmapPDFExporter.generatePDF(
            project: project,
            floorPlanImage: floorPlanImage,
            heatmapOverlay: vm.heatmapOverlayImage,
            visualization: .signalStrength
        )

        #expect(pdfData != nil)
        #expect(pdfData!.count > 0)

        // Verify it's valid PDF data (starts with %PDF)
        let pdfString = String(data: pdfData!.prefix(5), encoding: .ascii)
        #expect(pdfString?.hasPrefix("%PDF") == true)
    }

    @Test func pdfExporterHandlesEmptyPoints() {
        let floorPlan = FloorPlan(
            imageData: makeTestPNGData(),
            widthMeters: 0,
            heightMeters: 0,
            pixelWidth: 100,
            pixelHeight: 80,
            origin: .drawn
        )
        let project = SurveyProject(name: "Empty", floorPlan: floorPlan)
        let image = NSImage(data: makeTestPNGData())!

        // Should still generate (even with 0 points — the caller checks canExportPDF)
        let pdfData = HeatmapPDFExporter.generatePDF(
            project: project,
            floorPlanImage: image,
            heatmapOverlay: nil,
            visualization: .signalStrength
        )

        #expect(pdfData != nil)
    }

    // MARK: - New Project

    @Test func createNewProjectSetsFloorPlan() {
        let vm = HeatmapSurveyViewModel()

        vm.createNewProject(name: "My Survey")

        #expect(vm.hasFloorPlan == true)
        #expect(vm.project?.name == "My Survey")
        #expect(vm.project?.floorPlan.pixelWidth == 1000)
        #expect(vm.project?.floorPlan.pixelHeight == 800)
        #expect(vm.project?.floorPlan.origin == .drawn)
    }

    @Test func createNewProjectResetsState() async {
        let (vm, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        #expect(vm.summaryStats.count == 1)

        vm.createNewProject(name: "Fresh Project")

        #expect(vm.summaryStats.count == 0)
        #expect(vm.currentSavePath == nil)
        #expect(vm.isCalibrated == false)
        #expect(vm.undoStack.isEmpty)
        #expect(vm.redoStack.isEmpty)
    }

    @Test func createNewProjectCustomDimensions() {
        let vm = HeatmapSurveyViewModel()

        vm.createNewProject(name: "Custom", canvasWidth: 500, canvasHeight: 300)

        #expect(vm.project?.floorPlan.pixelWidth == 500)
        #expect(vm.project?.floorPlan.pixelHeight == 300)
    }

    // MARK: - Drawn Floor Plan

    @Test func applyDrawnFloorPlanCreatesProject() {
        let vm = HeatmapSurveyViewModel()
        let imageData = makeTestPNGData(width: 800, height: 600)

        vm.applyDrawnFloorPlan(name: "Drawn Office", imageData: imageData)

        #expect(vm.hasFloorPlan == true)
        #expect(vm.project?.name == "Drawn Office")
        #expect(vm.project?.floorPlan.pixelWidth == 800)
        #expect(vm.project?.floorPlan.pixelHeight == 600)
        #expect(vm.project?.floorPlan.origin == .drawn)
    }

    @Test func applyDrawnFloorPlanWithEmptyDataShowsError() {
        let vm = HeatmapSurveyViewModel()

        vm.applyDrawnFloorPlan(name: "Bad", imageData: Data())

        #expect(vm.showingError == true)
        #expect(vm.hasFloorPlan == false)
    }

    @Test func applyDrawnFloorPlanResetsState() async {
        let (vm, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        let imageData = makeTestPNGData(width: 600, height: 400)

        vm.applyDrawnFloorPlan(name: "New Drawing", imageData: imageData)

        #expect(vm.currentSavePath == nil)
        #expect(vm.isCalibrated == false)
        #expect(vm.undoStack.isEmpty)
    }

    @Test func drawnFloorPlanUsableForSurvey() async {
        let engine = MockMeasurementEngine()
        let vm = HeatmapSurveyViewModel(measurementEngine: engine)
        let imageData = makeTestPNGData(width: 800, height: 600)

        vm.applyDrawnFloorPlan(name: "Survey Base", imageData: imageData)
        #expect(vm.hasFloorPlan == true)

        // Should be able to take measurements on the drawn floor plan
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        #expect(vm.project?.measurementPoints.count == 1)

        await vm.takeMeasurement(at: CGPoint(x: 0.2, y: 0.2))
        await vm.takeMeasurement(at: CGPoint(x: 0.8, y: 0.8))
        #expect(vm.project?.measurementPoints.count == 3)
        #expect(vm.heatmapOverlayImage != nil)
    }

    // MARK: - Finder Double-Click (onOpenURL)

    @Test func loadProjectFromFinderURL() throws {
        let (vm, _) = makeVMWithFloorPlan()
        guard let project = vm.project else {
            Issue.record("Expected project")
            return
        }

        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("finder_test.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try SurveyFileManager.save(project, to: bundleURL)

        // Simulate Finder double-click by loading from URL
        let vm2 = HeatmapSurveyViewModel()
        vm2.loadProject(from: bundleURL)

        #expect(vm2.hasFloorPlan == true)
        #expect(vm2.project?.name == project.name)
        #expect(vm2.currentSavePath == bundleURL)
    }

    // MARK: - Error Handling

    @Test func loadMissingBundleShowsError() {
        let vm = HeatmapSurveyViewModel()
        let fakeURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing.netmonsurvey")

        vm.loadProject(from: fakeURL)

        #expect(vm.showingError == true)
        #expect(vm.errorMessage != nil)
    }

    @Test func loadCorruptBundleShowsError() {
        let vm = HeatmapSurveyViewModel()
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt_export.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        try? FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try? Data("invalid json".utf8).write(to: bundleURL.appendingPathComponent("survey.json"))

        vm.loadProject(from: bundleURL)

        #expect(vm.showingError == true)
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Multiple Projects

    @Test func canSwitchBetweenProjects() async throws {
        let (vm, engine) = makeVMWithFloorPlan()

        // Create and save project 1
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        guard let project1 = vm.project else {
            Issue.record("Expected project 1")
            return
        }
        let url1 = FileManager.default.temporaryDirectory.appendingPathComponent("project1.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: url1) }
        try SurveyFileManager.save(project1, to: url1)

        // Create project 2 with different data
        vm.createNewProject(name: "Project 2")
        engine.setMockRSSI(-80)
        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))
        guard let project2 = vm.project else {
            Issue.record("Expected project 2")
            return
        }
        let url2 = FileManager.default.temporaryDirectory.appendingPathComponent("project2.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: url2) }
        try SurveyFileManager.save(project2, to: url2)

        // Load project 1 back
        vm.loadProject(from: url1)
        #expect(vm.project?.measurementPoints.count == 1)

        // Load project 2 back
        vm.loadProject(from: url2)
        #expect(vm.project?.measurementPoints.count == 2)
        #expect(vm.project?.name == "Project 2")
    }

    // MARK: - Save As

    @Test func saveProjectAsCreatesNewPath() throws {
        let (vm, _) = makeVMWithFloorPlan()
        guard let project = vm.project else {
            Issue.record("Expected project")
            return
        }

        // Simulate saving to an initial path
        let url1 = FileManager.default.temporaryDirectory.appendingPathComponent("original.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: url1) }
        try SurveyFileManager.save(project, to: url1)
        vm.loadProject(from: url1)
        #expect(vm.currentSavePath == url1)

        // After "Save As", the path should change
        // (We can't test NSSavePanel, but we can verify the concept)
        let url2 = FileManager.default.temporaryDirectory.appendingPathComponent("copy.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: url2) }
        try SurveyFileManager.save(project, to: url2)

        // Verify both files exist
        #expect(FileManager.default.fileExists(atPath: url1.path))
        #expect(FileManager.default.fileExists(atPath: url2.path))
    }

    // MARK: - resetProjectState

    @Test func resetProjectStateClearsAllMutableState() async {
        let (vm, _) = makeVMWithFloorPlan()

        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "10"
        vm.applyCalibration()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        vm.resetProjectState()

        #expect(vm.isCalibrated == false)
        #expect(vm.pixelsPerMeter == 0)
        #expect(vm.scaleBarLabel.isEmpty)
        #expect(vm.scaleBarFraction == 0)
        #expect(vm.currentSavePath == nil)
        #expect(vm.undoStack.isEmpty)
        #expect(vm.redoStack.isEmpty)
        #expect(vm.selectedPointID == nil)
        #expect(vm.inspectedPointID == nil)
        #expect(vm.heatmapOverlayImage == nil)
        #expect(vm.summaryStats == SummaryStats.empty)
    }
}
