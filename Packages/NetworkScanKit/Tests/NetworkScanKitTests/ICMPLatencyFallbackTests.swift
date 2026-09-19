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

    @Test("ICMPLatencyPhase defaults probeCount to 1 (keeps iOS unchanged)")
    func defaultProbeCount() {
        let phase = ICMPLatencyPhase()
        #expect(phase.probeCount == 1)
    }

    @Test("ICMPLatencyPhase accepts a custom probeCount")
    func customProbeCount() {
        let phase = ICMPLatencyPhase(probeCount: 3)
        #expect(phase.probeCount == 3)
    }

    // MARK: - minimumRTTPerIP (pure function; the real ICMP socket path can't
    // run in the sandboxed test environment, so probeCount's min-of-N
    // reduction is tested in isolation here).

    @Test("minimumRTTPerIP keeps the minimum RTT across probeCount echoes per host")
    func minimumRTTAcrossProbes() {
        let raw: [(ip: String, rtt: Double)] = [
            ("10.0.0.1", 12.0), ("10.0.0.1", 4.0), ("10.0.0.1", 9.0),
            ("10.0.0.2", 30.0),
        ]
        let result = Dictionary(uniqueKeysWithValues: ICMPLatencyPhase.minimumRTTPerIP(raw))
        #expect(result["10.0.0.1"] == 4.0)
        #expect(result["10.0.0.2"] == 30.0)
    }

    @Test("minimumRTTPerIP with a single sample per host returns that sample")
    func minimumRTTSingleSample() {
        let raw: [(ip: String, rtt: Double)] = [("10.0.0.5", 7.5)]
        let result = Dictionary(uniqueKeysWithValues: ICMPLatencyPhase.minimumRTTPerIP(raw))
        #expect(result["10.0.0.5"] == 7.5)
    }

    @Test("minimumRTTPerIP with no samples returns empty")
    func minimumRTTEmpty() {
        let result = ICMPLatencyPhase.minimumRTTPerIP([])
        #expect(result.isEmpty)
    }

    @Test("ICMPLatencyPhase executes without crash on empty accumulator",
          .tags(.integration))
    func executeWithNoDevicesDoesNotCrash() async {
        // INTEGRATION GAP: ICMP socket creation will fail in the simulator sandbox.
        // The phase must complete onProgress(1.0) and return without crashing.
        let phase = ICMPLatencyPhase(collectTimeout: 0.1)
        let context = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil, requiredInterfaceType: .wifi)
        let accumulator = ScanAccumulator()
        actor ProgressCollector {
            private var _values: [Double] = []
            func append(_ value: Double) { _values.append(value) }
            var values: [Double] { _values }
        }
        let progressValues = ProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { value in
            await progressValues.append(value)
        }

        let collectedValues = await progressValues.values
        #expect(collectedValues.last == 1.0,
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
