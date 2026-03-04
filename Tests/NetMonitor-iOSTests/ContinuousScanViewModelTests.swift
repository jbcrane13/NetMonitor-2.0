import Foundation
import Testing
@testable import NetMonitor_iOS
@testable import NetMonitorCore

// MARK: - ContinuousScanViewModel Tests

@Suite("ContinuousScanViewModel")
@MainActor
struct ContinuousScanViewModelTests {

    // MARK: - Initialization

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
}
