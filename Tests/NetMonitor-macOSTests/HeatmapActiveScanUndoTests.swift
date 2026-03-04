import AppKit
import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

// MARK: - Test Helpers

/// Creates a minimal valid PNG image data for testing.
private func makeTestPNGData(width: Int = 100, height: Int = 80) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let cgImage = context.makeImage()
    else {
        return Data()
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:]) ?? Data()
}

/// Writes test PNG data to a temporary file and returns the URL.
private func makeTestPNGFile(name: String = "test_floorplan.png", width: Int = 100, height: Int = 80) -> URL {
    let data = makeTestPNGData(width: width, height: height)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? data.write(to: url)
    return url
}

// MARK: - Active Scan, Undo/Redo, Save/Load, Error Handling Tests

@Suite("HeatmapSurveyViewModel — Active Scan & Undo")
@MainActor
struct HeatmapActiveScanUndoTests {

    // MARK: - Factory

    private func makeVMWithFloorPlan() -> (HeatmapSurveyViewModel, MockMeasurementEngine, MockCoreWLANService) {
        let engine = MockMeasurementEngine()
        let wlanService = MockCoreWLANService()
        let vm = HeatmapSurveyViewModel(measurementEngine: engine, coreWLANService: wlanService)
        let url = makeTestPNGFile(width: 1000, height: 500)
        vm.loadFloorPlan(from: url)
        return (vm, engine, wlanService)
    }

    // MARK: - Active Scan Mode

    @Test func activeScanModeDefaultsToFalse() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.isActiveScanMode == false)
    }

    @Test func activeScanModeCanBeToggled() {
        let vm = HeatmapSurveyViewModel()
        vm.isActiveScanMode = true
        #expect(vm.isActiveScanMode == true)
        vm.isActiveScanMode = false
        #expect(vm.isActiveScanMode == false)
    }

    @Test func activeScanCallsTakeActiveMeasurement() async {
        let (vm, _, _) = makeVMWithFloorPlan()
        vm.isActiveScanMode = true

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        #expect(vm.project?.measurementPoints.count == 1)
        let point = vm.project?.measurementPoints.first
        // Active measurement should have speed/latency data
        #expect(point?.downloadSpeed == 150.0)
        #expect(point?.uploadSpeed == 50.0)
        #expect(point?.latency == 5.0)
    }

    @Test func passiveScanDoesNotCaptureSpeedData() async {
        let (vm, _, _) = makeVMWithFloorPlan()
        vm.isActiveScanMode = false

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        let point = vm.project?.measurementPoints.first
        #expect(point?.downloadSpeed == nil)
        #expect(point?.uploadSpeed == nil)
        #expect(point?.latency == nil)
    }

    @Test func activeMeasurementProgressResetAfterMeasurement() async {
        let (vm, _, _) = makeVMWithFloorPlan()
        vm.isActiveScanMode = true

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        // Progress should be nil after measurement completes
        #expect(vm.activeMeasurementProgress == nil)
    }

    // MARK: - Undo / Redo — Placement

    @Test func undoRemovesLastPlacedPoint() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        #expect(vm.project?.measurementPoints.count == 2)

        vm.undo()

        #expect(vm.project?.measurementPoints.count == 1)
        #expect(vm.undoStack.count == 1)
        #expect(vm.redoStack.count == 1)
    }

    @Test func undoMultiplePlacements() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))
        #expect(vm.project?.measurementPoints.count == 3)

        vm.undo()
        vm.undo()
        vm.undo()

        #expect(vm.project?.measurementPoints.count == 0)
        #expect(vm.undoStack.isEmpty)
        #expect(vm.redoStack.count == 3)
    }

    @Test func redoRestoresUndonePoint() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        vm.undo()
        #expect(vm.project?.measurementPoints.count == 0)

        vm.redo()

        #expect(vm.project?.measurementPoints.count == 1)
        #expect(vm.project?.measurementPoints.first?.floorPlanX == 0.5)
    }

    @Test func newPlacementClearsRedoStack() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        vm.undo()
        #expect(vm.redoStack.count == 1)

        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))
        #expect(vm.redoStack.isEmpty)
    }

    // MARK: - Undo / Redo — Deletion

    @Test func undoRestoresDeletedPoint() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        guard let pointID = vm.project?.measurementPoints.first?.id
        else {
            Issue.record("Expected measurement point")
            return
        }

        vm.removeMeasurementPoint(id: pointID)
        #expect(vm.project?.measurementPoints.count == 0)

        vm.undo()
        #expect(vm.project?.measurementPoints.count == 1)
        #expect(vm.project?.measurementPoints.first?.id == pointID)
    }

    @Test func redoReDeletesRestoredPoint() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        guard let pointID = vm.project?.measurementPoints.first?.id
        else {
            Issue.record("Expected measurement point")
            return
        }

        vm.removeMeasurementPoint(id: pointID)
        vm.undo()
        #expect(vm.project?.measurementPoints.count == 1)

        vm.redo()
        #expect(vm.project?.measurementPoints.count == 0)
    }

    @Test func undoDeletionRestoresAtOriginalIndex() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))
        guard let middlePointID = vm.project?.measurementPoints[1].id
        else {
            Issue.record("Expected measurement point at index 1")
            return
        }

        vm.removeMeasurementPoint(id: middlePointID)
        vm.undo()

        // Middle point should be back at index 1
        #expect(vm.project?.measurementPoints.count == 3)
        #expect(vm.project?.measurementPoints[1].id == middlePointID)
    }

    @Test func canUndoAndCanRedoCorrect() async {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.canUndo == false)
        #expect(vm.canRedo == false)

        let (vm2, _, _) = makeVMWithFloorPlan()
        await vm2.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        #expect(vm2.canUndo == true)
        #expect(vm2.canRedo == false)

        vm2.undo()
        #expect(vm2.canUndo == false)
        #expect(vm2.canRedo == true)
    }

    @Test func undoWithEmptyStackDoesNothing() {
        let vm = HeatmapSurveyViewModel()
        vm.undo() // Should not crash
        #expect(vm.undoStack.isEmpty)
    }

    @Test func redoWithEmptyStackDoesNothing() {
        let vm = HeatmapSurveyViewModel()
        vm.redo() // Should not crash
        #expect(vm.redoStack.isEmpty)
    }

    @Test func undoUpdatesHeatmapOverlay() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))
        #expect(vm.heatmapOverlayImage != nil)

        // Undo one point → drops below 3, overlay should be nil
        vm.undo()
        #expect(vm.heatmapOverlayImage == nil)
    }

    @Test func undoUpdatesSummaryStats() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        #expect(vm.summaryStats.count == 1)

        vm.undo()
        #expect(vm.summaryStats.count == 0)
    }

    // MARK: - Measurement Inspection

    @Test func inspectedPointIDDefaultsToNil() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.inspectedPointID == nil)
        #expect(vm.inspectedPoint == nil)
    }

    @Test func inspectedPointReturnsCorrectPoint() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        guard let pointID = vm.project?.measurementPoints.first?.id
        else {
            Issue.record("Expected measurement point")
            return
        }

        vm.inspectedPointID = pointID
        #expect(vm.inspectedPoint?.id == pointID)
        #expect(vm.inspectedPoint?.floorPlanX == 0.5)
    }

    @Test func deletingInspectedPointClearsInspection() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        guard let pointID = vm.project?.measurementPoints.first?.id
        else {
            Issue.record("Expected measurement point")
            return
        }

        vm.inspectedPointID = pointID
        vm.removeMeasurementPoint(id: pointID)

        #expect(vm.inspectedPointID == nil)
    }

    // MARK: - Save / Load

    @Test func loadProjectFromBundleRestoresState() throws {
        let engine = MockMeasurementEngine()
        let vm = HeatmapSurveyViewModel(measurementEngine: engine)
        let url = makeTestPNGFile(width: 400, height: 300)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        guard let currentProject = vm.project else {
            Issue.record("Expected project to exist")
            return
        }

        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_load.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try SurveyFileManager.save(currentProject, to: bundleURL)

        let vm2 = HeatmapSurveyViewModel()
        vm2.loadProject(from: bundleURL)

        #expect(vm2.hasFloorPlan == true)
        #expect(vm2.project?.name == currentProject.name)
        #expect(vm2.project?.floorPlan.pixelWidth == 400)
        #expect(vm2.project?.floorPlan.pixelHeight == 300)
    }

    @Test func loadCorruptProjectShowsError() {
        let vm = HeatmapSurveyViewModel()
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt_test.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        try? FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try? Data("not valid json".utf8).write(
            to: bundleURL.appendingPathComponent("survey.json")
        )

        vm.loadProject(from: bundleURL)

        #expect(vm.showingError == true)
        #expect(vm.errorMessage != nil)
        #expect(vm.hasFloorPlan == false)
    }

    @Test func loadProjectResetsUndoStacks() async {
        let engine = MockMeasurementEngine()
        let vm = HeatmapSurveyViewModel(measurementEngine: engine)
        let url = makeTestPNGFile(width: 200, height: 150)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        #expect(vm.canUndo == true)

        guard let currentProject = vm.project else {
            Issue.record("Expected project")
            return
        }
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_undo_reset.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try? SurveyFileManager.save(currentProject, to: bundleURL)

        vm.loadProject(from: bundleURL)
        #expect(vm.canUndo == false)
        #expect(vm.canRedo == false)
    }

    @Test func loadProjectRestoresCalibration() throws {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters
        vm.applyCalibration()
        #expect(vm.isCalibrated == true)

        guard let currentProject = vm.project else {
            Issue.record("Expected project")
            return
        }
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_calib.netmonsurvey")
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try SurveyFileManager.save(currentProject, to: bundleURL)

        let vm2 = HeatmapSurveyViewModel()
        vm2.loadProject(from: bundleURL)

        #expect(vm2.isCalibrated == true)
        #expect(vm2.pixelsPerMeter > 0)
    }

    // MARK: - Error Handling

    @Test func measurementWithoutEngineDoesNotCrash() async {
        let vm = HeatmapSurveyViewModel(measurementEngine: nil)
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        #expect(vm.project?.measurementPoints.isEmpty == true)
    }

    @Test func loadNonExistentBundleShowsError() {
        let vm = HeatmapSurveyViewModel()
        let fakeURL = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent.netmonsurvey")

        vm.loadProject(from: fakeURL)

        #expect(vm.showingError == true)
        #expect(vm.errorMessage != nil)
    }
}
