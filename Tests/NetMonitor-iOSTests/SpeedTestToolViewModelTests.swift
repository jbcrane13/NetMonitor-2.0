import Testing
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
        #expect(vm.downloadSpeedText == "500.0 Mbps")
    }

    @Test func downloadSpeedTextGbps() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.downloadSpeed = 2000.0
        #expect(vm.downloadSpeedText == "2.0 Gbps")
    }

    @Test func uploadSpeedTextMbps() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.uploadSpeed = 100.5
        #expect(vm.uploadSpeedText == "100.5 Mbps")
    }

    @Test func uploadSpeedTextGbpsThreshold() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.uploadSpeed = 1000.0
        #expect(vm.uploadSpeedText == "1.0 Gbps")
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
