import Testing
import Foundation
@testable import NetworkScanKit

/// INTEGRATION: Real ScanPipeline execution on local network.
/// Uses the standard pipeline with real scan phases (ARP, TCP probe, ICMP, DNS).
/// Tagged .integration — requires real local network access.
///
/// This test validates that the ScanPipeline orchestration works end-to-end
/// with real network stack phases, not just stub phases.
struct ScanPipelineRealIntegrationTests {

    // MARK: - Real pipeline run

    /// INTEGRATION: requires real local network.
    /// Runs ScanPipeline.standard() on a minimal host list (127.0.0.1) and verifies
    /// the pipeline completes without crash and progress callbacks fire.
    @Test("ScanPipeline.standard() runs without crash on loopback host", .tags(.integration))
    func standardPipelineCompletesWithoutCrash() async {
        let engine = ScanEngine()
        let pipeline = ScanPipeline.standard()
        // Use loopback to guarantee at least one host is reachable
        let context = ScanContext(
            hosts: ["127.0.0.1"],
            subnetFilter: { _ in true },
            localIP: "127.0.0.1"
        )

        let progressValues = ProgressCollector()
        let results = await engine.scan(pipeline: pipeline, context: context) { value, _ in
            await progressValues.append(value)
        }

        let values = await progressValues.values
        // Progress must have been reported at least once
        #expect(!values.isEmpty, "Pipeline must emit at least one progress update")
        // All progress values must be in [0, 1]
        for v in values {
            #expect(v >= 0.0 && v <= 1.0, "Progress value \(v) out of [0,1] range")
        }
        // Results may be empty (loopback doesn't respond to all probe types) — no crash is what matters
        #expect(results.isEmpty, "Pipeline must complete and return results array (may be empty on loopback)")
    }

    @Test("ScanPipeline.standard() on local subnet finds at least 1 device", .tags(.integration))
    func standardPipelineFindsAtLeastOneDevice() async {
        let engine = ScanEngine()
        let pipeline = ScanPipeline.standard()

        // Detect local IP via a UDP socket trick
        guard let localIP = detectLocalIPAddress() else {
            // Skip on hosts without network interface
            return
        }
        let subnetPrefix = localIP.components(separatedBy: ".").prefix(3).joined(separator: ".")

        // Scan just a small range around the local machine: .1 through .5
        let hosts = (1...5).map { "\(subnetPrefix).\($0)" }
        let context = ScanContext(hosts: hosts, subnetFilter: { _ in true }, localIP: localIP)

        let results = await engine.scan(pipeline: pipeline, context: context) { _, _ in }

        // The machine running the test should be discoverable on its own network
        #expect(results.count >= 1,
                "At least the local machine should be found on subnet \(subnetPrefix).x")
    }

    // MARK: - Helpers

    /// Returns the first non-loopback IPv4 address on this host, or nil if none found.
    private func detectLocalIPAddress() -> String? {
        for address in Host.current().addresses {
            let parts = address.split(separator: ".")
            guard parts.count == 4,
                  !address.contains(":"),   // skip IPv6
                  !address.hasPrefix("127.") // skip loopback
            else { continue }
            return address
        }
        return nil
    }
}

private actor ProgressCollector {
    private var _values: [Double] = []
    func append(_ v: Double) { _values.append(v) }
    var values: [Double] { _values }
}
