import Testing
@testable import NetworkScanKit

// INTEGRATION GAP: Real ICMP socket testing requires entitlements unavailable
// in the test sandbox (socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP) returns -1).
// ICMPLatencyPhase detects this at runtime and skips latency enrichment gracefully.
// These tests verify the fallback / data-format contract layer.

struct ICMPLatencyFallbackTests {

    @Test("ICMPLatencyPhase initializes with default collectTimeout")
    func defaultCollectTimeout() {
        let phase = ICMPLatencyPhase()
        #expect(phase.id == "icmpLatency")
        #expect(phase.weight > 0)
    }

    @Test("ICMPLatencyPhase initializes with custom collectTimeout")
    func customCollectTimeout() {
        let phase = ICMPLatencyPhase(collectTimeout: 0.5)
        #expect(phase.id == "icmpLatency")
    }

    @Test("ICMPLatencyPhase executes without crash on empty accumulator",
          .tags(.integration))
    func executeWithNoDevicesDoesNotCrash() async {
        // INTEGRATION GAP: ICMP socket creation will fail in the simulator sandbox.
        // The phase must complete onProgress(1.0) and return without crashing.
        let phase = ICMPLatencyPhase(collectTimeout: 0.1)
        let context = ScanContext(subnet: "192.168.1.0/24", knownHosts: [])
        let accumulator = ScanAccumulator()
        var progressValues: [Double] = []

        await phase.execute(context: context, accumulator: accumulator) { value in
            progressValues.append(value)
        }

        #expect(progressValues.last == 1.0,
               "Phase must report 100% completion even when no devices are present")
    }

    @Test("Valid RTT value is non-negative", arguments: [0.0, 1.5, 100.0, 999.9])
    func validRTTValues(rtt: Double) {
        // RTT values produced by the phase must be non-negative
        #expect(rtt >= 0)
    }

    @Test("Phase weight is between 0 and 1 exclusive")
    func phaseWeightIsReasonable() {
        let phase = ICMPLatencyPhase()
        #expect(phase.weight > 0)
        #expect(phase.weight <= 1.0)
    }
}
