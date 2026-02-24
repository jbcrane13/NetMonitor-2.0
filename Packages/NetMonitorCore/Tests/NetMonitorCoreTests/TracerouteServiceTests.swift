import Testing
import Foundation
@testable import NetMonitorCore

/// Tests for TracerouteService state and TracerouteHop model logic.
/// Network-dependent tracing (ICMPSocket, DNS resolution) is excluded.
@Suite("TracerouteService")
struct TracerouteServiceTests {

    // MARK: - Default configuration (accessed via async actor)

    @Test("defaultMaxHops is 30")
    func defaultMaxHopsIs30() async {
        let service = TracerouteService()
        let maxHops = await service.defaultMaxHops
        #expect(maxHops == 30)
    }

    @Test("defaultTimeout is 2.0 seconds")
    func defaultTimeoutIs2Seconds() async {
        let service = TracerouteService()
        let timeout = await service.defaultTimeout
        #expect(timeout == 2.0)
    }

    // MARK: - Initial state

    @Test("running is false before any trace")
    func runningIsFalseBeforeAnyTrace() async {
        let service = TracerouteService()
        let running = await service.running
        #expect(running == false)
    }

    // MARK: - stop() state management

    @Test("stop() is idempotent when no trace is active")
    func stopIsIdempotentWithNoActiveTrace() async {
        let service = TracerouteService()
        await service.stop()
        await service.stop()
        let running = await service.running
        #expect(running == false)
    }

    // MARK: - TracerouteHop struct pure logic

    @Test("hop with zero times has nil averageTime")
    func hopWithZeroTimesHasNilAverageTime() {
        let hop = TracerouteHop(hopNumber: 3, ipAddress: "10.0.0.1", times: [])
        #expect(hop.averageTime == nil)
    }

    @Test("hop isTimeout is false when times are present")
    func hopIsNotTimeoutWhenTimesPresent() {
        let hop = TracerouteHop(hopNumber: 1, ipAddress: "192.168.1.1", times: [5.0, 6.0])
        #expect(hop.isTimeout == false)
    }

    @Test("hop isTimeout is true when flag is set")
    func hopIsTimeoutWhenFlagSet() {
        let hop = TracerouteHop(hopNumber: 2, isTimeout: true)
        #expect(hop.isTimeout == true)
    }

    @Test("hop hopNumber is stored correctly")
    func hopNumberStoredCorrectly() {
        let hop = TracerouteHop(hopNumber: 15, ipAddress: "1.2.3.4", times: [10.0])
        #expect(hop.hopNumber == 15)
    }

    @Test("hop with hostname stores it correctly")
    func hopHostnameStoredCorrectly() {
        let hop = TracerouteHop(hopNumber: 1, ipAddress: "8.8.8.8", hostname: "dns.google", times: [20.0])
        #expect(hop.hostname == "dns.google")
        #expect(hop.ipAddress == "8.8.8.8")
    }

    @Test("hop times array is stored in order")
    func hopTimesStoredInOrder() {
        let times = [1.1, 2.2, 3.3]
        let hop = TracerouteHop(hopNumber: 1, times: times)
        #expect(hop.times == times)
    }
}
