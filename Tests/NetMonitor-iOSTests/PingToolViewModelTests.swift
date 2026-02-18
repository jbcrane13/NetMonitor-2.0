import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("PingToolViewModel")
@MainActor
struct PingToolViewModelTests {

    @Test func initialState() {
        let vm = PingToolViewModel(pingService: MockPingService())
        #expect(vm.host == "")
        #expect(vm.isRunning == false)
        #expect(vm.results.isEmpty)
        #expect(vm.statistics == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func initialHostIsSet() {
        let vm = PingToolViewModel(pingService: MockPingService(), initialHost: "192.168.1.1")
        #expect(vm.host == "192.168.1.1")
    }

    @Test func availablePingCountsAreCorrect() {
        let vm = PingToolViewModel(pingService: MockPingService())
        #expect(vm.availablePingCounts == [4, 10, 20, 50, 100])
    }

    @Test func canStartPingFalseWhenHostEmpty() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = ""
        #expect(vm.canStartPing == false)
    }

    @Test func canStartPingFalseWhenHostIsWhitespace() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "   "
        #expect(vm.canStartPing == false)
    }

    @Test func canStartPingTrueWithValidHost() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "192.168.1.1"
        #expect(vm.canStartPing == true)
    }

    @Test func canStartPingFalseWhileRunning() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "192.168.1.1"
        vm.isRunning = true
        #expect(vm.canStartPing == false)
    }

    @Test func clearResultsResetsState() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.results = [PingResult(sequence: 1, host: "test", ttl: 64, time: 10.0)]
        vm.statistics = PingStatistics(
            host: "test", transmitted: 1, received: 1,
            packetLoss: 0, minTime: 10, maxTime: 10, avgTime: 10
        )
        vm.errorMessage = "Some error"

        vm.clearResults()

        #expect(vm.results.isEmpty)
        #expect(vm.statistics == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func startPingSetsIsRunningImmediately() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "192.168.1.1"
        vm.startPing()
        #expect(vm.isRunning == true)
    }

    @Test func startPingClearsExistingResultsSynchronously() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "192.168.1.1"
        vm.results = [PingResult(sequence: 1, host: "old", ttl: 64, time: 5.0)]
        vm.startPing()
        // clearResults() is called synchronously before spawning the Task
        #expect(vm.results.isEmpty)
    }

    @Test func startPingIgnoredWhenCannotStart() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "" // cannot start
        vm.startPing()
        #expect(vm.isRunning == false)
    }

    @Test func stopPingSetsIsRunningFalse() {
        let vm = PingToolViewModel(pingService: MockPingService())
        vm.host = "192.168.1.1"
        vm.startPing()
        vm.stopPing()
        #expect(vm.isRunning == false)
    }
}
