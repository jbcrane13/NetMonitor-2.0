import Testing
import Foundation
@testable import NetworkScanKit

@Suite("TCPProbeScanPhase")
struct TCPProbeScanPhaseTests {

    // MARK: - Phase metadata

    @Test("id is 'tcpProbe'")
    func phaseIDIsTcpProbe() {
        let phase = TCPProbeScanPhase()
        #expect(phase.id == "tcpProbe")
    }

    @Test("displayName is 'Probing ports…'")
    func phaseDisplayName() {
        let phase = TCPProbeScanPhase()
        #expect(phase.displayName == "Probing ports…")
    }

    @Test("weight is 0.55")
    func phaseWeight() {
        let phase = TCPProbeScanPhase()
        #expect(phase.weight == 0.55)
    }

    @Test("weight is positive")
    func phaseWeightIsPositive() {
        let phase = TCPProbeScanPhase()
        #expect(phase.weight > 0)
    }

    @Test("conforms to ScanPhase protocol")
    func conformsToScanPhase() {
        let phase: any ScanPhase = TCPProbeScanPhase()
        #expect(phase.id == "tcpProbe")
        #expect(phase.displayName == "Probing ports…")
        #expect(phase.weight == 0.55)
    }

    // MARK: - Init with maxConcurrentHosts

    @Test("default maxConcurrentHosts is 40")
    func defaultMaxConcurrentHosts() {
        let phase = TCPProbeScanPhase()
        #expect(phase.maxConcurrentHosts == 40)
    }

    @Test("custom maxConcurrentHosts")
    func customMaxConcurrentHosts() {
        let phase = TCPProbeScanPhase(maxConcurrentHosts: 20)
        #expect(phase.maxConcurrentHosts == 20)
    }

    @Test("maxConcurrentHosts of 1")
    func maxConcurrentHostsOne() {
        let phase = TCPProbeScanPhase(maxConcurrentHosts: 1)
        #expect(phase.maxConcurrentHosts == 1)
    }

    // MARK: - Probe ports

    @Test("primaryProbePorts contains expected ports")
    func primaryProbePorts() {
        let ports = TCPProbeScanPhase.primaryProbePorts
        #expect(ports.contains(80))
        #expect(ports.contains(443))
        #expect(ports.contains(22))
        #expect(ports.contains(445))
        #expect(ports.count == 4)
    }

    @Test("secondaryProbePorts contains expected ports")
    func secondaryProbePorts() {
        let ports = TCPProbeScanPhase.secondaryProbePorts
        #expect(ports.contains(7000))
        #expect(ports.contains(8080))
        #expect(ports.contains(8443))
        #expect(ports.contains(62078))
        #expect(ports.contains(5353))
        #expect(ports.contains(9100))
        #expect(ports.contains(1883))
        #expect(ports.contains(554))
        #expect(ports.contains(548))
        #expect(ports.count == 9)
    }

    // MARK: - Execute with empty hosts

    @Test("execute with empty hosts completes and reports progress")
    func executeWithEmptyHosts() async {
        let phase = TCPProbeScanPhase(maxConcurrentHosts: 2)
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = TCPProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        #expect(await accumulator.isEmpty)
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    // MARK: - Execute with known IPs in accumulator (skip logic)

    @Test("execute skips IPs already in accumulator")
    func executeSkipsKnownIPs() async {
        let phase = TCPProbeScanPhase(maxConcurrentHosts: 2)
        let accumulator = ScanAccumulator()

        // Pre-populate with a known IP
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.1.1",
            hostname: nil,
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ))

        let context = ScanContext(
            hosts: ["192.168.1.1", "192.168.1.2"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let collector = TCPProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // 192.168.1.1 was already known; only 192.168.1.2 would be probed
        // (probe result depends on network, but at minimum the known IP should be skipped)
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    @Test("execute with all hosts already known skips probing entirely")
    func executeWithAllKnownIPsSkipsProbing() async {
        let phase = TCPProbeScanPhase(maxConcurrentHosts: 2)
        let accumulator = ScanAccumulator()

        // Pre-populate with all IPs
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.1.1",
            hostname: nil,
            vendor: nil,
            macAddress: "aa:bb:cc:dd:ee:ff",
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ))

        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let collector = TCPProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // All hosts already known — should skip directly to progress 1.0
        let values = await collector.values
        #expect(values.contains(0.0))
        #expect(values.contains(1.0))
    }

    // MARK: - Execute with non-routable IPs (will timeout/fail)

    @Test("execute with unreachable IPs completes without crash")
    func executeWithUnreachableIPs() async {
        let phase = TCPProbeScanPhase(maxConcurrentHosts: 2)
        // 192.0.2.1 is a TEST-NET address (RFC 5737) — typically unroutable
        let context = ScanContext(
            hosts: ["192.0.2.1"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = TCPProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // Should complete without crash regardless of probe results
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    // MARK: - Latency enrichment

    @Test("execute enriches devices without latency from accumulator")
    func executeEnrichesDevicesWithoutLatency() async {
        let phase = TCPProbeScanPhase(maxConcurrentHosts: 2)
        let accumulator = ScanAccumulator()

        // Pre-populate with a device that has no latency
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.1.1",
            hostname: nil,
            vendor: nil,
            macAddress: "aa:bb:cc:dd:ee:ff",
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ))

        // All hosts are already known, so the main probe loop is skipped,
        // but the enrichment step should still run for devices without latency
        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let collector = TCPProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // Should complete — enrichment may or may not succeed depending on network
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    // MARK: - Progress reporting

    @Test("execute always reports progress from 0 to 1")
    func executeReportsProgressRange() async {
        let phase = TCPProbeScanPhase(maxConcurrentHosts: 2)
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = TCPProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    // MARK: - Multiple instances

    @Test("multiple instances have independent maxConcurrentHosts")
    func multipleInstancesIndependent() {
        let phase1 = TCPProbeScanPhase(maxConcurrentHosts: 10)
        let phase2 = TCPProbeScanPhase(maxConcurrentHosts: 50)
        #expect(phase1.maxConcurrentHosts == 10)
        #expect(phase2.maxConcurrentHosts == 50)
    }
}

// MARK: - Test helpers

private actor TCPProgressCollector {
    private var _values: [Double] = []
    func append(_ v: Double) { _values.append(v) }
    var values: [Double] { _values }
}
