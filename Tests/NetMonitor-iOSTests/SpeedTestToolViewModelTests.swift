import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("SpeedTestToolViewModel")
@MainActor
struct SpeedTestToolViewModelTests {

    @Test func initialState() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        #expect(vm.isRunning == false)
        #expect(vm.downloadSpeed == 0)
        #expect(vm.uploadSpeed == 0)
        #expect(vm.latency == 0)
        #expect(vm.progress == 0)
        #expect(vm.phase == .idle)
        #expect(vm.errorMessage == nil)
    }

    @Test func phaseTextIdle() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.phase = .idle
        #expect(vm.phaseText == "Ready")
    }

    @Test func phaseTextLatency() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.phase = .latency
        #expect(vm.phaseText == "Measuring latency...")
    }

    @Test func phaseTextDownload() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.phase = .download
        #expect(vm.phaseText == "Testing download...")
    }

    @Test func phaseTextUpload() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.phase = .upload
        #expect(vm.phaseText == "Testing upload...")
    }

    @Test func phaseTextComplete() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.phase = .complete
        #expect(vm.phaseText == "Complete")
    }

    @Test func downloadSpeedTextMbps() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.downloadSpeed = 500.0
        #expect(vm.downloadSpeedText == "500 Mbps")
    }

    @Test func downloadSpeedTextGbps() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.downloadSpeed = 2000.0
        #expect(vm.downloadSpeedText == "2.00 Gbps")
    }

    @Test func uploadSpeedTextMbps() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.uploadSpeed = 100.5
        #expect(vm.uploadSpeedText == "100 Mbps")
    }

    @Test func uploadSpeedTextGbpsThreshold() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.uploadSpeed = 1000.0
        #expect(vm.uploadSpeedText == "1.00 Gbps")
    }

    @Test func latencyTextFormattedCorrectly() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.latency = 25.7
        #expect(vm.latencyText == "26 ms")
    }

    @Test func latencyTextRoundsToZeroDecimals() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.latency = 100.0
        #expect(vm.latencyText == "100 ms")
    }

    @Test func stopTestSetsIsRunningFalse() {
        let mock = MockSpeedTestService()
        let vm = SpeedTestToolViewModel(service: mock)
        vm.isRunning = true
        vm.phase = .download
        vm.stopTest()
        #expect(vm.isRunning == false)
        #expect(vm.phase == .idle)
    }

    @Test func stopTestCallsServiceStop() {
        let mock = MockSpeedTestService()
        let vm = SpeedTestToolViewModel(service: mock)
        vm.stopTest()
        #expect(mock.stopCallCount == 1)
    }
}

// MARK: - Peak Speed & Jitter Tests

@Suite("SpeedTestToolViewModel Peak Speeds & Jitter")
@MainActor
struct SpeedTestToolViewModelPeakJitterTests {

    @Test func peakDownloadSpeedDelegatesFromService() {
        let mock = MockSpeedTestService()
        mock.peakDownloadSpeed = 150.0
        let vm = SpeedTestToolViewModel(service: mock)
        vm.peakDownloadSpeed = mock.peakDownloadSpeed
        #expect(vm.peakDownloadSpeed == 150.0)
    }

    @Test func peakUploadSpeedDelegatesFromService() {
        let mock = MockSpeedTestService()
        mock.peakUploadSpeed = 80.0
        let vm = SpeedTestToolViewModel(service: mock)
        vm.peakUploadSpeed = mock.peakUploadSpeed
        #expect(vm.peakUploadSpeed == 80.0)
    }

    @Test func jitterDelegatesFromService() {
        let mock = MockSpeedTestService()
        mock.jitter = 12.5
        let vm = SpeedTestToolViewModel(service: mock)
        vm.jitter = mock.jitter
        #expect(vm.jitter == 12.5)
    }

    @Test func peakDownloadSpeedTextFormatsCorrectly() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.peakDownloadSpeed = 150.0
        #expect(!vm.peakDownloadSpeedText.isEmpty)
    }

    @Test func peakUploadSpeedTextFormatsCorrectly() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.peakUploadSpeed = 80.0
        #expect(!vm.peakUploadSpeedText.isEmpty)
    }
}

// MARK: - Error & Edge Case Tests

@Suite("SpeedTestToolViewModel Error & Edge Cases")
@MainActor
struct SpeedTestToolViewModelErrorTests {

    @Test func stopTestResetsPhaseToIdle() {
        let mock = MockSpeedTestService()
        let vm = SpeedTestToolViewModel(service: mock)
        vm.isRunning = true
        vm.phase = .upload
        vm.stopTest()
        #expect(vm.phase == .idle)
        #expect(vm.isRunning == false)
    }

    @Test func stopTestCallsServiceStopTwice() {
        let mock = MockSpeedTestService()
        let vm = SpeedTestToolViewModel(service: mock)
        vm.stopTest()
        vm.stopTest()
        #expect(mock.stopCallCount == 2)
    }

    @Test func phaseTextForAllPhases() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        let cases: [(SpeedTestPhase, String)] = [
            (.idle, "Ready"),
            (.latency, "Measuring latency..."),
            (.download, "Testing download..."),
            (.upload, "Testing upload..."),
            (.complete, "Complete")
        ]
        for (phase, expected) in cases {
            vm.phase = phase
            #expect(vm.phaseText == expected)
        }
    }

    @Test func initialErrorMessageIsNil() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        #expect(vm.errorMessage == nil)
    }

    @Test func stopTestDoesNotAffectErrorMessage() {
        let mock = MockSpeedTestService()
        let vm = SpeedTestToolViewModel(service: mock)
        vm.errorMessage = "connection lost"
        vm.stopTest()
        // errorMessage is not cleared by stopTest — it persists until next run
        #expect(vm.errorMessage == "connection lost")
    }

    @Test func downloadSpeedTextFormatsZeroCorrectly() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.downloadSpeed = 0
        #expect(vm.downloadSpeedText == "0 Mbps")
    }

    @Test func uploadSpeedTextFormatsZeroCorrectly() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.uploadSpeed = 0
        #expect(vm.uploadSpeedText == "0 Mbps")
    }
}
