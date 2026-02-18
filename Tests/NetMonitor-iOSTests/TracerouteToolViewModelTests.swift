import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("TracerouteToolViewModel")
@MainActor
struct TracerouteToolViewModelTests {

    @Test func initialState() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        #expect(vm.host == "")
        #expect(vm.maxHops == 30)
        #expect(vm.isRunning == false)
        #expect(vm.hops.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func initialHostIsSet() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService(), initialHost: "8.8.8.8")
        #expect(vm.host == "8.8.8.8")
    }

    @Test func availableMaxHopsAreCorrect() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        #expect(vm.availableMaxHops == [15, 30, 64])
    }

    @Test func canStartTraceFalseWhenHostEmpty() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.host = ""
        #expect(vm.canStartTrace == false)
    }

    @Test func canStartTraceFalseWhenHostIsWhitespace() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.host = "  "
        #expect(vm.canStartTrace == false)
    }

    @Test func canStartTraceTrueWithValidHost() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.host = "google.com"
        #expect(vm.canStartTrace == true)
    }

    @Test func canStartTraceFalseWhileRunning() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.host = "google.com"
        vm.isRunning = true
        #expect(vm.canStartTrace == false)
    }

    @Test func completedHopsMatchesHopsCount() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.hops = [
            TracerouteHop(hopNumber: 1, ipAddress: "192.168.1.1"),
            TracerouteHop(hopNumber: 2, ipAddress: "10.0.0.1")
        ]
        #expect(vm.completedHops == 2)
    }

    @Test func completedHopsZeroInitially() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        #expect(vm.completedHops == 0)
    }

    @Test func clearResultsResetsState() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.hops = [TracerouteHop(hopNumber: 1, ipAddress: "192.168.1.1")]
        vm.errorMessage = "timeout"
        vm.clearResults()
        #expect(vm.hops.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func startTraceSetsIsRunningImmediately() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.host = "google.com"
        vm.startTrace()
        #expect(vm.isRunning == true)
    }

    @Test func stopTraceSetsIsRunningFalse() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.host = "google.com"
        vm.startTrace()
        vm.stopTrace()
        #expect(vm.isRunning == false)
    }

    @Test func startTraceIgnoredWhenCannotStart() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.host = ""
        vm.startTrace()
        #expect(vm.isRunning == false)
    }
}
