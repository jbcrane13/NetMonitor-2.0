import Foundation
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - RoomPlanScannerViewModelTests

@MainActor
struct RoomPlanScannerViewModelTests {

    // MARK: - State Management Tests

    @Test func initialStateIsIdle() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.scanState == .idle)
    }

    @Test func initialCompletedBlueprintIsNil() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.completedBlueprint == nil)
    }

    @Test func initialPreviewImageIsNil() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.previewImage == nil)
    }

    @Test func initialExportedFileURLIsNil() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.exportedFileURL == nil)
    }

    @Test func initialShowShareSheetIsFalse() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.showShareSheet == false)
    }

    @Test func initialShowNameEditorIsFalse() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.showNameEditor == false)
    }

    @Test func resetScanClearsAllState() {
        let vm = RoomPlanScannerViewModel()
        // Mutate state before resetting
        vm.scanState = .complete
        vm.showShareSheet = true
        vm.exportedFileURL = URL(fileURLWithPath: "/tmp/test.netmonblueprint")
        vm.projectName = "Custom Name"

        vm.resetScan()

        #expect(vm.scanState == .idle)
        #expect(vm.completedBlueprint == nil)
        #expect(vm.previewImage == nil)
        #expect(vm.exportedFileURL == nil)
    }

    @Test func handleScanErrorSetsErrorState() {
        let vm = RoomPlanScannerViewModel()
        let testError = NSError(domain: "TestDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Scanner disconnected",
        ])

        vm.handleScanError(testError)

        #expect(vm.scanState == .error("Scanner disconnected"))
    }

    @Test func handleScanErrorPreservesMessage() {
        let vm = RoomPlanScannerViewModel()
        let testError = NSError(domain: "RoomPlan", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "LiDAR sensor unavailable",
        ])

        vm.handleScanError(testError)

        if case .error(let message) = vm.scanState {
            #expect(message == "LiDAR sensor unavailable")
        } else {
            Issue.record("Expected .error state but got \(vm.scanState)")
        }
    }

    // MARK: - State Transition Tests

    @Test func scanStateTransitionIdleToScanning() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.scanState == .idle)

        vm.scanState = .scanning
        #expect(vm.scanState == .scanning)
    }

    @Test func scanStateTransitionToProcessing() {
        let vm = RoomPlanScannerViewModel()
        vm.scanState = .processing
        #expect(vm.scanState == .processing)
    }

    @Test func scanStateTransitionToComplete() {
        let vm = RoomPlanScannerViewModel()
        vm.scanState = .complete
        #expect(vm.scanState == .complete)
    }

    @Test func resetFromCompleteReturnsToIdle() {
        let vm = RoomPlanScannerViewModel()
        vm.scanState = .complete

        vm.resetScan()

        #expect(vm.scanState == .idle)
    }

    @Test func resetFromErrorReturnsToIdle() {
        let vm = RoomPlanScannerViewModel()
        vm.scanState = .error("Something went wrong")

        vm.resetScan()

        #expect(vm.scanState == .idle)
    }

    @Test func resetFromProcessingReturnsToIdle() {
        let vm = RoomPlanScannerViewModel()
        vm.scanState = .processing

        vm.resetScan()

        #expect(vm.scanState == .idle)
    }

    @Test func resetClearsCompletedBlueprint() {
        let vm = RoomPlanScannerViewModel()
        // completedBlueprint is private(set), so we verify it's nil after reset
        // (it starts nil and reset should keep it nil)
        vm.resetScan()
        #expect(vm.completedBlueprint == nil)
    }

    @Test func resetClearsPreviewImage() {
        let vm = RoomPlanScannerViewModel()
        vm.resetScan()
        #expect(vm.previewImage == nil)
    }

    @Test func resetClearsExportedFileURL() {
        let vm = RoomPlanScannerViewModel()
        vm.exportedFileURL = URL(fileURLWithPath: "/tmp/test.netmonblueprint")

        vm.resetScan()

        #expect(vm.exportedFileURL == nil)
    }

    // MARK: - Property Default Tests

    @Test func defaultProjectName() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.projectName == "Room Scan")
    }

    @Test func defaultBuildingName() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.buildingName.isEmpty)
    }

    @Test func defaultFloorLabel() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.floorLabel == "Floor 1")
    }

    @Test func defaultFloorNumber() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.floorNumber == 1)
    }

    // MARK: - Property Mutation Tests

    @Test func projectNameCanBeChanged() {
        let vm = RoomPlanScannerViewModel()
        vm.projectName = "Office Layout"
        #expect(vm.projectName == "Office Layout")
    }

    @Test func buildingNameCanBeChanged() {
        let vm = RoomPlanScannerViewModel()
        vm.buildingName = "Building A"
        #expect(vm.buildingName == "Building A")
    }

    @Test func floorLabelCanBeChanged() {
        let vm = RoomPlanScannerViewModel()
        vm.floorLabel = "Basement"
        #expect(vm.floorLabel == "Basement")
    }

    @Test func floorNumberCanBeChanged() {
        let vm = RoomPlanScannerViewModel()
        vm.floorNumber = 3
        #expect(vm.floorNumber == 3)
    }

    // MARK: - Export Tests

    @Test func exportBlueprintWithNoCompletedBlueprintDoesNothing() {
        let vm = RoomPlanScannerViewModel()
        #expect(vm.completedBlueprint == nil)

        // Should not crash and should not set showShareSheet
        vm.exportBlueprint()

        #expect(vm.showShareSheet == false)
        #expect(vm.exportedFileURL == nil)
    }

    @Test func exportBlueprintWithNoCompletedBlueprintPreservesState() {
        let vm = RoomPlanScannerViewModel()
        vm.scanState = .idle
        vm.projectName = "Test Project"

        vm.exportBlueprint()

        #expect(vm.scanState == .idle)
        #expect(vm.projectName == "Test Project")
    }

    // MARK: - ScanState Equatable Tests

    @Test func scanStateIdleEquality() {
        #expect(RoomPlanScanState.idle == RoomPlanScanState.idle)
    }

    @Test func scanStateScanningEquality() {
        #expect(RoomPlanScanState.scanning == RoomPlanScanState.scanning)
    }

    @Test func scanStateProcessingEquality() {
        #expect(RoomPlanScanState.processing == RoomPlanScanState.processing)
    }

    @Test func scanStateCompleteEquality() {
        #expect(RoomPlanScanState.complete == RoomPlanScanState.complete)
    }

    @Test func scanStateErrorEquality() {
        #expect(RoomPlanScanState.error("msg") == RoomPlanScanState.error("msg"))
    }

    @Test func scanStateErrorInequalityDifferentMessages() {
        #expect(RoomPlanScanState.error("a") != RoomPlanScanState.error("b"))
    }

    @Test func scanStateIdleNotEqualToScanning() {
        #expect(RoomPlanScanState.idle != RoomPlanScanState.scanning)
    }

    // MARK: - Reset Does Not Clear User-Editable Fields

    @Test func resetDoesNotClearProjectName() {
        let vm = RoomPlanScannerViewModel()
        vm.projectName = "My Custom Project"

        vm.resetScan()

        // resetScan() only clears scan artifacts, not user-editable metadata
        #expect(vm.projectName == "My Custom Project")
    }

    @Test func resetDoesNotClearBuildingName() {
        let vm = RoomPlanScannerViewModel()
        vm.buildingName = "HQ"

        vm.resetScan()

        #expect(vm.buildingName == "HQ")
    }

    @Test func resetDoesNotClearFloorLabel() {
        let vm = RoomPlanScannerViewModel()
        vm.floorLabel = "Second Floor"

        vm.resetScan()

        #expect(vm.floorLabel == "Second Floor")
    }

    // MARK: - Multiple Error Handling

    @Test func multipleErrorsOverwriteState() {
        let vm = RoomPlanScannerViewModel()
        let error1 = NSError(domain: "Test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "First error",
        ])
        let error2 = NSError(domain: "Test", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Second error",
        ])

        vm.handleScanError(error1)
        #expect(vm.scanState == .error("First error"))

        vm.handleScanError(error2)
        #expect(vm.scanState == .error("Second error"))
    }

    // MARK: - Integration Gap

    // INTEGRATION GAP: processCapturedRoom() requires a real CapturedRoom from RoomPlan framework.
    // CapturedRoom cannot be constructed in tests without a live RoomCaptureSession.
    // Wall extraction (extractWallSegments), room label extraction (extractRoomLabels),
    // and bounds calculation (calculateBounds) are tested indirectly through the full scan flow.
    // Manual verification required on LiDAR device.
    //
    // The following behaviors cannot be unit-tested without hardware:
    // - processCapturedRoom() transitions scanState from .processing to .complete
    // - processCapturedRoom() populates completedBlueprint with wall segments and room labels
    // - processCapturedRoom() generates a previewImage from SVG rendering
    // - exportBlueprint() with a real completedBlueprint sets showShareSheet = true
    // - exportBlueprint() updates metadata (projectName, buildingName, floorLabel, floorNumber)
    // - calculateBounds() returns correct width/height/offset from wall segments
    // - extractRoomLabels() computes normalized centroid positions
}
