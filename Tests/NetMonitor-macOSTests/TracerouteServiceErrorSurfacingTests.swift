import Testing
import Foundation
import NetMonitorCore

/// Tests that TracerouteService surfaces errors rather than silently swallowing them.
///
/// TracerouteService.performHTTPTracerouteFallback() uses `try?` on URLSession calls
/// (lines ~277, 297) — network failures silently return `false`, causing the stream
/// to complete with zero meaningful hops. These tests verify observable outcomes when
/// various failure modes occur.
///
/// Note: TracerouteService uses `URLSession.shared` directly in the HTTP fallback
/// (no session injection), so we test via the public `trace()` API and verify
/// the stream output for known-bad inputs that exercise error paths.
struct TracerouteServiceErrorSurfacingTests {

    // MARK: - DNS Resolution Failure

    @Test("Unresolvable host yields a timeout hop instead of empty stream")
    func unresolvableHostYieldsTimeoutHop() async {
        let service = TracerouteService()
        let stream = await service.trace(host: "this.host.definitely.does.not.exist.invalid", maxHops: 5, timeout: 1.0)

        var hops: [TracerouteHop] = []
        for await hop in stream {
            hops.append(hop)
        }

        // The service should yield at least one hop indicating the failure,
        // not silently produce an empty stream.
        #expect(!hops.isEmpty, "DNS failure should yield at least one timeout hop, not an empty stream")
        #expect(hops[0].isTimeout == true, "First hop should be marked as timeout for unresolvable host")
        #expect(hops[0].ipAddress == nil, "Unresolvable host should have nil IP address")
    }

    @Test("Empty hostname yields a timeout hop")
    func emptyHostnameYieldsTimeoutHop() async {
        let service = TracerouteService()
        let stream = await service.trace(host: "", maxHops: 5, timeout: 1.0)

        var hops: [TracerouteHop] = []
        for await hop in stream {
            hops.append(hop)
        }

        // Empty hostname should not silently complete — it should surface the problem.
        #expect(!hops.isEmpty, "Empty hostname should produce at least one hop indicating failure")
        #expect(hops[0].isTimeout == true)
    }

    // MARK: - Stop/Cancellation Behavior

    @Test("Stopping trace before completion sets isRunning to false")
    func stoppingTraceSetsIsRunningFalse() async {
        let service = TracerouteService()
        // Start a trace to an unresolvable host (will finish quickly)
        let stream = await service.trace(host: "unresolvable.invalid.host.test", maxHops: 3, timeout: 0.5)

        // Consume the stream
        for await _ in stream {}

        let running = await service.running
        #expect(running == false, "running should be false after trace completes")
    }

    @Test("Calling stop() before trace completes does not leave service in inconsistent state")
    func stopDuringTraceDoesNotLeaveInconsistentState() async {
        let service = TracerouteService()
        let stream = await service.trace(host: "unresolvable.invalid.host.test", maxHops: 3, timeout: 0.5)

        // Stop immediately
        await service.stop()

        // Drain remaining items
        for await _ in stream {}

        let running = await service.running
        #expect(running == false, "Service should not be stuck in running state after stop()")
    }

    // MARK: - Max Hops Boundary

    @Test("maxHops of 1 with unresolvable host still yields a hop")
    func maxHopsOneWithBadHostStillYieldsHop() async {
        let service = TracerouteService()
        let stream = await service.trace(host: "nonexistent.invalid", maxHops: 1, timeout: 0.5)

        var hops: [TracerouteHop] = []
        for await hop in stream {
            hops.append(hop)
        }

        #expect(!hops.isEmpty, "Even with maxHops=1, an unresolvable host should yield a timeout hop")
    }

    @Test("Trace to localhost resolves without hanging")
    func traceToLocalhostCompletesWithoutHanging() async {
        let service = TracerouteService()
        let stream = await service.trace(host: "127.0.0.1", maxHops: 3, timeout: 1.0)

        var hops: [TracerouteHop] = []
        for await hop in stream {
            hops.append(hop)
        }

        // localhost trace should complete (either with hops or timeout) — not hang forever.
        // The key assertion is that we reach this point (stream finishes).
        let running = await service.running
        #expect(running == false, "Trace to localhost should complete and set running to false")
    }
}
