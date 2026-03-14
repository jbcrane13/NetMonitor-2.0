import Testing
import Foundation
@testable import NetMonitorCore

/// Integration tests for TracerouteService that exercise the real ICMP/TCP probe
/// stack against locally reachable destinations.
///
/// Tagged .integration — require a functioning network stack (loopback at minimum).
/// Run selectively with: swift test --filter "integration"
///
/// Note: ICMP socket availability on macOS test runners depends on sandbox entitlements.
/// The service falls back gracefully to TCP probing when ICMP sockets are unavailable,
/// so these tests are valid in both environments.
struct TracerouteServiceIntegrationTests {

    // MARK: - Loopback trace

    @Test("trace to loopback produces at least one hop", .tags(.integration))
    func traceToLoopbackProducesAtLeastOneHop() async {
        let service = TracerouteService()
        var hops: [TracerouteHop] = []
        for await hop in await service.trace(host: "127.0.0.1", maxHops: 3, timeout: 5.0) {
            hops.append(hop)
        }
        // Loopback trace should produce at least 1 hop (may be a timeout * for restricted ICMP
        // or a real echo reply — both are valid outcomes)
        #expect(!hops.isEmpty, "Traceroute to loopback must produce at least one result")
    }

    @Test("trace to loopback produces hops with monotonically increasing hop numbers", .tags(.integration))
    func traceToLoopbackHopNumbersAreMonotonicallyIncreasing() async {
        let service = TracerouteService()
        var hops: [TracerouteHop] = []
        for await hop in await service.trace(host: "127.0.0.1", maxHops: 5, timeout: 5.0) {
            hops.append(hop)
        }
        guard hops.count >= 2 else { return }
        for i in 1..<hops.count {
            #expect(hops[i].hopNumber > hops[i - 1].hopNumber,
                    "Hop \(i) number \(hops[i].hopNumber) must be greater than hop \(i-1) number \(hops[i-1].hopNumber)")
        }
    }

    @Test("trace to loopback does not produce more hops than maxHops", .tags(.integration))
    func traceToLoopbackDoesNotExceedMaxHops() async {
        let maxHops = 3
        let service = TracerouteService()
        var hops: [TracerouteHop] = []
        for await hop in await service.trace(host: "127.0.0.1", maxHops: maxHops, timeout: 5.0) {
            hops.append(hop)
        }
        #expect(hops.count <= maxHops,
                "Trace produced \(hops.count) hops but maxHops was \(maxHops)")
    }

    @Test("trace stream finishes (does not hang) within reasonable time for loopback", .tags(.integration))
    func traceToLoopbackFinishesWithinTimeout() async throws {
        let service = TracerouteService()
        let start = Date()
        // Use maxHops=1 to ensure the stream terminates quickly
        for await _ in await service.trace(host: "127.0.0.1", maxHops: 1, timeout: 3.0) {
            // consume
        }
        let elapsed = Date().timeIntervalSince(start)
        // Stream must finish within 15 seconds even on a slow CI host
        #expect(elapsed < 15.0, "Traceroute stream did not finish in time: \(elapsed)s elapsed")
    }

    // MARK: - Unresolvable host

    @Test("trace to unresolvable host yields at least one timeout hop", .tags(.integration))
    func traceToUnresolvableHostYieldsTimeoutHop() async {
        let service = TracerouteService()
        var hops: [TracerouteHop] = []
        for await hop in await service.trace(
            host: "this.host.does.not.exist.invalid",
            maxHops: 2,
            timeout: 2.0
        ) {
            hops.append(hop)
        }
        // Unresolvable host: TracerouteService yields a single timeout hop (isTimeout=true)
        // when hostname resolution fails, then finishes the stream.
        #expect(!hops.isEmpty, "Must yield at least one hop even for unresolvable hosts")
        let hasTimeout = hops.contains { $0.isTimeout }
        #expect(hasTimeout, "At least one hop must be a timeout for an unresolvable host")
    }

    // MARK: - Stop during trace

    @Test("stop() during active trace causes stream to finish without hang", .tags(.integration))
    func stopDuringTraceFinishesStreamWithoutHang() async throws {
        let service = TracerouteService()

        // Use a slow external target so the trace stays running when we stop it.
        // 10.255.255.1 is a non-routable address — all hops will time out,
        // giving us a reliable slow trace to interrupt.
        let traceTask = Task {
            var count = 0
            for await _ in await service.trace(host: "10.255.255.1", maxHops: 30, timeout: 2.0) {
                count += 1
                if count >= 1 {
                    // Got at least one hop — now stop
                    await service.stop()
                    break
                }
            }
            return count
        }

        let count = await traceTask.value
        // We broke after 1 hop and called stop() — the stream must not hang after that
        #expect(count >= 1, "Stream must have yielded at least one hop before stop()")

        // Verify the service is no longer running
        let isRunning = await service.running
        #expect(isRunning == false, "Service must not be in running state after stop()")
    }

    @Test("running is false after trace to loopback completes naturally", .tags(.integration))
    func runningIsFalseAfterNaturalCompletion() async {
        let service = TracerouteService()
        for await _ in await service.trace(host: "127.0.0.1", maxHops: 1, timeout: 3.0) {
            // consume all hops
        }
        let isRunning = await service.running
        #expect(isRunning == false, "running must be false after the stream finishes naturally")
    }

    // MARK: - Hop structure validation

    @Test("all hops from loopback trace have valid hop numbers starting at 1", .tags(.integration))
    func loopbackHopsHaveValidHopNumbers() async {
        let service = TracerouteService()
        var hops: [TracerouteHop] = []
        for await hop in await service.trace(host: "127.0.0.1", maxHops: 3, timeout: 5.0) {
            hops.append(hop)
        }
        for hop in hops {
            #expect(hop.hopNumber >= 1, "Hop number must be at least 1, got \(hop.hopNumber)")
        }
        if let first = hops.first {
            #expect(first.hopNumber == 1, "First hop must have hop number 1, got \(first.hopNumber)")
        }
    }

    @Test("non-timeout hops from loopback trace have non-negative RTT values", .tags(.integration))
    func loopbackNonTimeoutHopsHaveNonNegativeRTTs() async {
        let service = TracerouteService()
        for await hop in await service.trace(host: "127.0.0.1", maxHops: 3, timeout: 5.0) {
            if !hop.isTimeout {
                for time in hop.times {
                    #expect(time >= 0.0, "RTT must be non-negative, got \(time) for hop \(hop.hopNumber)")
                }
            }
        }
    }

    @Test("non-timeout hops have at least one RTT value", .tags(.integration))
    func nonTimeoutHopsHaveAtLeastOneRTT() async {
        let service = TracerouteService()
        for await hop in await service.trace(host: "127.0.0.1", maxHops: 3, timeout: 5.0) {
            if !hop.isTimeout {
                #expect(!hop.times.isEmpty,
                        "Non-timeout hop \(hop.hopNumber) must have at least one RTT value")
            }
        }
    }
}
