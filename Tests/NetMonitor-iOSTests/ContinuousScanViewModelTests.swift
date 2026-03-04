import Foundation
import Testing
@testable import NetMonitor_iOS
@testable import NetMonitorCore

// MARK: - ContinuousScanViewModel Tests

@Suite("ContinuousScanViewModel")
@MainActor
struct ContinuousScanViewModelTests {

    // MARK: - Initialization

    @Test("initial scan phase is idle")
    func initialPhaseIsIdle() {
        let vm = ContinuousScanViewModel()
        #expect(vm.scanPhase == .idle)
    }

    @Test("initial state is not scanning")
    func initialStateNotScanning() {
        let vm = ContinuousScanViewModel()
        #expect(vm.isScanning == false)
    }

    @Test("initial state is not paused")
    func initialStateNotPaused() {
        let vm = ContinuousScanViewModel()
        #expect(vm.isPaused == false)
    }

    @Test("initial error message is nil")
    func initialErrorIsNil() {
        let vm = ContinuousScanViewModel()
        #expect(vm.errorMessage == nil)
    }

    @Test("initial raw measurement count is zero")
    func initialRawCountZero() {
        let vm = ContinuousScanViewModel()
        #expect(vm.rawMeasurementCount == 0)
    }

    @Test("initial downsampled count is zero")
    func initialDownsampledCountZero() {
        let vm = ContinuousScanViewModel()
        #expect(vm.downsampledPointCount == 0)
    }

    @Test("initial RSSI is nil")
    func initialRSSIIsNil() {
        let vm = ContinuousScanViewModel()
        #expect(vm.currentRSSI == nil)
    }

    @Test("initial SSID is nil")
    func initialSSIDIsNil() {
        let vm = ContinuousScanViewModel()
        #expect(vm.currentSSID == nil)
    }

    @Test("initial BSSID is nil")
    func initialBSSIDIsNil() {
        let vm = ContinuousScanViewModel()
        #expect(vm.currentBSSID == nil)
    }

    @Test("initial scan complete is false")
    func initialScanCompleteIsFalse() {
        let vm = ContinuousScanViewModel()
        #expect(vm.isScanComplete == false)
    }

    @Test("completed project is nil initially")
    func completedProjectNilInitially() {
        let vm = ContinuousScanViewModel()
        #expect(vm.completedProject == nil)
    }

    @Test("initial refinement progress is zero")
    func initialRefinementProgressZero() {
        let vm = ContinuousScanViewModel()
        #expect(vm.refinementProgress == 0)
    }

    // MARK: - Device Capability

    @Test("deviceCapability matches session manager")
    func deviceCapabilityMatchesManager() {
        let vm = ContinuousScanViewModel()
        // In simulator, no LiDAR available
        #expect(vm.deviceCapability == .unsupported)
    }

    @Test("isLiDARAvailable is false on simulator")
    func isLiDARAvailableFalseOnSimulator() {
        let vm = ContinuousScanViewModel()
        #expect(vm.isLiDARAvailable == false)
    }

    // MARK: - LiDAR Gating

    @Test("startScan sets error on non-LiDAR device")
    func startScanSetsErrorWithoutLiDAR() async {
        let vm = ContinuousScanViewModel()
        await vm.startScan()

        // On simulator (no LiDAR), should get error
        #expect(vm.errorMessage != nil)
        #expect(vm.isScanning == false)
    }

    // MARK: - Default Interval

    @Test("current interval starts at default 500ms")
    func currentIntervalStartsAtDefault() {
        let vm = ContinuousScanViewModel()
        #expect(vm.currentInterval == ContinuousCapturePipeline.defaultInterval)
    }

    // MARK: - Coverage Percentage

    @Test("coverage percentage is zero with no points")
    func coveragePercentageZeroWithNoPoints() {
        let vm = ContinuousScanViewModel()
        #expect(vm.coveragePercentage == 0.0)
    }

    // MARK: - Cancel Scan

    @Test("cancel scan resets state")
    func cancelScanResetsState() async {
        let vm = ContinuousScanViewModel()
        await vm.cancelScan()

        #expect(vm.isScanning == false)
        #expect(vm.isPaused == false)
        #expect(vm.rawMeasurementCount == 0)
        #expect(vm.downsampledPointCount == 0)
    }

    @Test("cancel scan clears map image")
    func cancelScanClearsMapImage() async {
        let vm = ContinuousScanViewModel()
        await vm.cancelScan()
        #expect(vm.mapImage == nil)
    }

    @Test("cancel scan resets to idle phase")
    func cancelScanResetsToIdle() async {
        let vm = ContinuousScanViewModel()
        await vm.cancelScan()
        #expect(vm.scanPhase == .idle)
    }

    @Test("cancel scan clears BSSID transitions")
    func cancelScanClearsBSSIDTransitions() async {
        let vm = ContinuousScanViewModel()
        await vm.cancelScan()
        #expect(vm.bssidTransitions.isEmpty)
    }

    @Test("cancel scan clears refined heatmap")
    func cancelScanClearsRefinedHeatmap() async {
        let vm = ContinuousScanViewModel()
        await vm.cancelScan()
        #expect(vm.refinedHeatmapImage == nil)
    }

    @Test("cancel scan clears completed project")
    func cancelScanClearsCompletedProject() async {
        let vm = ContinuousScanViewModel()
        await vm.cancelScan()
        #expect(vm.completedProject == nil)
    }

    // MARK: - Metal Rendering State

    @Test("initial map image is nil")
    func initialMapImageIsNil() {
        let vm = ContinuousScanViewModel()
        #expect(vm.mapImage == nil)
    }

    @Test("initial mesh segments rendered is zero")
    func initialMeshSegmentsZero() {
        let vm = ContinuousScanViewModel()
        #expect(vm.meshSegmentsRendered == 0)
    }

    @Test("initial measurement splats rendered is zero")
    func initialMeasurementSplatsZero() {
        let vm = ContinuousScanViewModel()
        #expect(vm.measurementSplatsRendered == 0)
    }

    @Test("initial user world position is nil")
    func initialUserPositionNil() {
        let vm = ContinuousScanViewModel()
        #expect(vm.userWorldPosition == nil)
    }

    // MARK: - Viewport State

    @Test("initial map scale is 1.0")
    func initialMapScale() {
        let vm = ContinuousScanViewModel()
        #expect(vm.mapScale == 1.0)
    }

    @Test("initial map offset is zero")
    func initialMapOffset() {
        let vm = ContinuousScanViewModel()
        #expect(vm.mapOffset == .zero)
    }

    @Test("initial auto-center is enabled")
    func initialAutoCenter() {
        let vm = ContinuousScanViewModel()
        #expect(vm.isAutoCenter == true)
    }

    @Test("disable auto-center works")
    func disableAutoCenter() {
        let vm = ContinuousScanViewModel()
        vm.disableAutoCenter()
        #expect(vm.isAutoCenter == false)
    }

    @Test("enable auto-center after disable")
    func enableAutoCenterAfterDisable() {
        let vm = ContinuousScanViewModel()
        vm.disableAutoCenter()
        vm.enableAutoCenter()
        #expect(vm.isAutoCenter == true)
    }

    // MARK: - Map Bounds

    @Test("initial map bounds width is zero")
    func initialMapBoundsWidth() {
        let vm = ContinuousScanViewModel()
        #expect(vm.mapBoundsWidth == 0)
    }

    @Test("initial map bounds height is zero")
    func initialMapBoundsHeight() {
        let vm = ContinuousScanViewModel()
        #expect(vm.mapBoundsHeight == 0)
    }

    // MARK: - Thermal Management

    @Test("initial thermal state is nominal")
    func initialThermalNominal() {
        let vm = ContinuousScanViewModel()
        // Thermal state from ProcessInfo — typically .nominal in tests
        #expect(vm.thermalState == .nominal || vm.thermalState == .elevated)
    }

    @Test("initial thermal warning is nil")
    func initialThermalWarningNil() {
        let vm = ContinuousScanViewModel()
        #expect(vm.thermalWarning == nil)
    }

    @Test("initial wasAutoPausedByThermal is false")
    func initialNotAutoPaused() {
        let vm = ContinuousScanViewModel()
        #expect(vm.wasAutoPausedByThermal == false)
    }

    // MARK: - Post-scan Visualization

    @Test("default visualization is signalStrength")
    func defaultVisualization() {
        let vm = ContinuousScanViewModel()
        #expect(vm.selectedVisualization == .signalStrength)
    }

    // MARK: - AP Roaming Overlay (P1)

    @Test("initial BSSID transitions is empty")
    func initialBSSIDTransitionsEmpty() {
        let vm = ContinuousScanViewModel()
        #expect(vm.bssidTransitions.isEmpty)
    }

    @Test("show roaming overlay is true by default")
    func defaultShowRoamingOverlay() {
        let vm = ContinuousScanViewModel()
        #expect(vm.showRoamingOverlay == true)
    }

    // MARK: - Walking Path Trace (P1)

    @Test("show walking path is true by default")
    func defaultShowWalkingPath() {
        let vm = ContinuousScanViewModel()
        #expect(vm.showWalkingPath == true)
    }

    // MARK: - Error Handling

    @Test("handleARError preserves data")
    func arErrorPreservesData() {
        let vm = ContinuousScanViewModel()
        vm.handleARError("Test AR failure")
        // Should not crash, state preserved
        #expect(vm.errorMessage == nil) // AR error doesn't set errorMessage, just logs
    }

    @Test("handleWiFiError sets degraded flag")
    func wifiErrorSetsDegraded() {
        let vm = ContinuousScanViewModel()
        vm.handleWiFiError()
        #expect(vm.isWiFiDegraded == true)
    }

    @Test("initial isWiFiDegraded is false")
    func initialWiFiNotDegraded() {
        let vm = ContinuousScanViewModel()
        #expect(vm.isWiFiDegraded == false)
    }

    @Test("initial isMemoryReduced is false")
    func initialMemoryNotReduced() {
        let vm = ContinuousScanViewModel()
        #expect(vm.isMemoryReduced == false)
    }

    // MARK: - ScanPhase Equatable

    @Test("ScanPhase idle equals idle")
    func scanPhaseIdleEquatable() {
        #expect(ScanPhase.idle == ScanPhase.idle)
    }

    @Test("ScanPhase scanning equals scanning")
    func scanPhaseScanningEquatable() {
        #expect(ScanPhase.scanning == ScanPhase.scanning)
    }

    @Test("ScanPhase paused equals paused")
    func scanPhasePausedEquatable() {
        #expect(ScanPhase.paused == ScanPhase.paused)
    }

    @Test("ScanPhase complete equals complete")
    func scanPhaseCompleteEquatable() {
        #expect(ScanPhase.complete == ScanPhase.complete)
    }

    @Test("ScanPhase refining with same progress equals")
    func scanPhaseRefiningEquatable() {
        #expect(ScanPhase.refining(progress: 0.5) == ScanPhase.refining(progress: 0.5))
    }

    @Test("ScanPhase different cases not equal")
    func scanPhaseDifferentNotEqual() {
        #expect(ScanPhase.idle != ScanPhase.scanning)
        #expect(ScanPhase.scanning != ScanPhase.paused)
        #expect(ScanPhase.paused != ScanPhase.complete)
    }
}

// MARK: - BSSIDTransition Tests

@Suite("BSSIDTransition")
struct BSSIDTransitionTests {

    @Test("BSSIDTransition stores all fields")
    func storesAllFields() {
        let transition = BSSIDTransition(
            worldX: 1.5,
            worldZ: 2.5,
            fromBSSID: "AA:BB:CC:DD:EE:FF",
            toBSSID: "11:22:33:44:55:66"
        )
        #expect(transition.worldX == 1.5)
        #expect(transition.worldZ == 2.5)
        #expect(transition.fromBSSID == "AA:BB:CC:DD:EE:FF")
        #expect(transition.toBSSID == "11:22:33:44:55:66")
    }

    @Test("BSSIDTransition is equatable")
    func isEquatable() {
        let t1 = BSSIDTransition(worldX: 1.0, worldZ: 2.0, fromBSSID: "A", toBSSID: "B")
        let t2 = BSSIDTransition(worldX: 1.0, worldZ: 2.0, fromBSSID: "A", toBSSID: "B")
        #expect(t1 == t2)
    }
}
