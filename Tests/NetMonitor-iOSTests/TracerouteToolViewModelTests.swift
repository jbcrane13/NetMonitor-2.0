import Testing
import Foundation
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

// MARK: - Error & Edge Case Tests

@Suite("TracerouteToolViewModel Error & Edge Cases")
@MainActor
struct TracerouteToolViewModelErrorTests {

    @Test func allTimeoutHopsAreAccumulated() async throws {
        let mock = MockTracerouteService()
        // Timeout hops have isTimeout: true
        mock.mockHops = [
            TracerouteHop(hopNumber: 1, ipAddress: nil, isTimeout: true),
            TracerouteHop(hopNumber: 2, ipAddress: nil, isTimeout: true),
            TracerouteHop(hopNumber: 3, ipAddress: "8.8.8.8", isTimeout: false)
        ]
        let vm = TracerouteToolViewModel(tracerouteService: mock)
        vm.host = "google.com"
        vm.startTrace()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.completedHops == 3)
        #expect(vm.hops[0].isTimeout == true)
        #expect(vm.hops[1].isTimeout == true)
        #expect(vm.hops[2].isTimeout == false)
    }

    @Test func maxHopsReachedStopsAtConfiguredLimit() async throws {
        let mock = MockTracerouteService()
        mock.mockHops = (1...15).map { TracerouteHop(hopNumber: $0, ipAddress: "10.0.0.\($0)") }
        let vm = TracerouteToolViewModel(tracerouteService: mock)
        vm.host = "example.com"
        vm.maxHops = 15
        vm.startTrace()
        try await Task.sleep(for: .milliseconds(200))
        // Service returned 15 hops matching the maxHops setting
        #expect(vm.completedHops == 15)
        #expect(vm.isRunning == false)
    }

    @Test func emptyHopsAfterTraceDoesNotSetErrorMessage() async throws {
        // The service returns no hops (e.g. unreachable host)
        let mock = MockTracerouteService()
        mock.mockHops = []
        let vm = TracerouteToolViewModel(tracerouteService: mock)
        vm.host = "unreachable.invalid"
        vm.startTrace()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.hops.isEmpty)
        #expect(vm.isRunning == false)
        // ViewModel does not set an error message on its own for empty results
        #expect(vm.errorMessage == nil)
    }

    @Test func clearResultsAlsoRemovesTimeoutHops() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.hops = [
            TracerouteHop(hopNumber: 1, ipAddress: nil),
            TracerouteHop(hopNumber: 2, ipAddress: "1.2.3.4")
        ]
        vm.errorMessage = "timeout"
        vm.clearResults()
        #expect(vm.hops.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func stopTraceDuringRunCallsServiceStop() async throws {
        let mock = MockTracerouteService()
        let vm = TracerouteToolViewModel(tracerouteService: mock)
        vm.host = "google.com"
        vm.startTrace()
        vm.stopTrace()
        try await Task.sleep(for: .milliseconds(100))
        #expect(mock.stopCallCount == 1)
    }
}
