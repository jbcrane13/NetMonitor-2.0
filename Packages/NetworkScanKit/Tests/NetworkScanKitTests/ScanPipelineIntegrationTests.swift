import Testing
@testable import NetworkScanKit

/// Additional ScanPipeline and ScanEngine integration tests.
/// Does NOT duplicate tests already in ScanPipelineTests.swift or ScanEngineTests.swift.
struct ScanPipelineIntegrationTests {

    // MARK: - Phase weight computation

    @Test("total weight of standard pipeline is the sum of all phase weights")
    func totalWeightOfStandardPipeline() {
        let pipeline = ScanPipeline.standard()
        let total = pipeline.steps.flatMap(\.phases).reduce(0.0) { $0 + $1.weight }
        #expect(total > 0)
    }

    @Test("each phase in standard pipeline has positive weight")
    func eachPhaseHasPositiveWeight() {
        let pipeline = ScanPipeline.standard()
        for step in pipeline.steps {
            for phase in step.phases {
                #expect(phase.weight > 0, "Phase \(phase.id) has non-positive weight")
            }
        }
    }

    @Test("remote pipeline total weight is positive")
    func remotePipelineTotalWeight() {
        let pipeline = ScanPipeline.forStrategy(.remote)
        let total = pipeline.steps.flatMap(\.phases).reduce(0.0) { $0 + $1.weight }
        #expect(total > 0)
    }

    // MARK: - Phase IDs in standard pipeline

    @Test("standard pipeline step 0 contains arp and bonjour phases")
    func standardStep0PhaseIDs() {
        let pipeline = ScanPipeline.standard()
        let ids = pipeline.steps[0].phases.map(\.id)
        #expect(ids.contains("arp"))
        #expect(ids.contains("bonjour"))
    }

    @Test("standard pipeline step 1 contains tcpProbe and ssdp phases")
    func standardStep1PhaseIDs() {
        let pipeline = ScanPipeline.standard()
        let ids = pipeline.steps[1].phases.map(\.id)
        #expect(ids.contains("tcpProbe"))
        #expect(ids.contains("ssdp"))
    }

    @Test("standard pipeline step 2 contains icmpLatency phase")
    func standardStep2PhaseID() {
        let pipeline = ScanPipeline.standard()
        #expect(pipeline.steps[2].phases[0].id == "icmpLatency")
    }

    @Test("standard pipeline step 3 contains reverseDNS phase")
    func standardStep3PhaseID() {
        let pipeline = ScanPipeline.standard()
        #expect(pipeline.steps[3].phases[0].id == "reverseDNS")
    }

    // MARK: - ScanEngine with empty pipeline

    @Test("ScanEngine with empty pipeline returns empty result immediately")
    func scanEngineEmptyPipelineReturnsEmpty() async {
        let engine = ScanEngine()
        let pipeline = ScanPipeline(steps: [])
        let counter = ProgressCounter()
        let results = await engine.scan(pipeline: pipeline, context: makeContext(hosts: [])) { _, _ in
            await counter.increment()
        }
        #expect(results.isEmpty)
        let count = await counter.value
        #expect(count == 0)
    }

    // MARK: - ScanEngine multiple sequential phases

    @Test("ScanEngine runs all sequential phases and accumulates devices")
    func scanEngineRunsAllSequentialPhases() async {
        let engine = ScanEngine()
        let phases = [
            StubPhase(id: "p1", weight: 1.0, ips: ["10.0.0.1"]),
            StubPhase(id: "p2", weight: 1.0, ips: ["10.0.0.2"]),
            StubPhase(id: "p3", weight: 1.0, ips: ["10.0.0.3"]),
        ]
        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: phases, concurrent: false)
        ])
        let results = await engine.scan(pipeline: pipeline, context: makeContext(hosts: [])) { _, _ in }
        let ips = Set(results.map(\.ipAddress))
        #expect(ips == Set(["10.0.0.1", "10.0.0.2", "10.0.0.3"]))
    }

    // MARK: - ScanEngine duplicate IP deduplication

    @Test("ScanEngine deduplicates devices with the same IP across phases")
    func scanEngineDuplicatesAreMerged() async {
        let engine = ScanEngine()
        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(
                phases: [
                    StubPhase(id: "a", weight: 1.0, ips: ["192.168.1.1"]),
                    StubPhase(id: "b", weight: 1.0, ips: ["192.168.1.1"]),
                ],
                concurrent: true
            )
        ])
        let results = await engine.scan(pipeline: pipeline, context: makeContext(hosts: [])) { _, _ in }
        #expect(results.count == 1)
        #expect(results[0].ipAddress == "192.168.1.1")
    }

    // MARK: - ScanEngine progress reporting

    @Test("ScanEngine reports progress values in [0,1] range")
    func scanEngineProgressInRange() async {
        let engine = ScanEngine()
        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(
                phases: [StubPhase(id: "x", weight: 2.0, ips: [])],
                concurrent: false
            )
        ])
        let collector = ProgressCollector()
        _ = await engine.scan(pipeline: pipeline, context: makeContext(hosts: [])) { value, _ in
            await collector.append(value)
        }
        let values = await collector.values
        for v in values {
            #expect(v >= 0.0 && v <= 1.0)
        }
    }

    // MARK: - ScanEngine reset

    @Test("ScanEngine reset after scan allows clean rescan")
    func scanEngineResetAllowsRescan() async {
        let engine = ScanEngine()
        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(
                phases: [StubPhase(id: "r", weight: 1.0, ips: ["172.16.0.1"])],
                concurrent: false
            )
        ])
        _ = await engine.scan(pipeline: pipeline, context: makeContext(hosts: [])) { _, _ in }
        #expect(await engine.accumulator.count == 1)

        await engine.reset()
        #expect(await engine.accumulator.isEmpty)

        let results2 = await engine.scan(pipeline: pipeline, context: makeContext(hosts: [])) { _, _ in }
        #expect(results2.count == 1)
    }

    // MARK: - Helpers

    private func makeContext(hosts: [String]) -> ScanContext {
        ScanContext(hosts: hosts, subnetFilter: { _ in true }, localIP: nil)
    }
}

// MARK: - Actor helpers for Sendable closure collection

private actor ProgressCounter {
    private var count = 0
    func increment() { count += 1 }
    var value: Int { count }
}

private actor ProgressCollector {
    private var _values: [Double] = []
    func append(_ v: Double) { _values.append(v) }
    var values: [Double] { _values }
}

// MARK: - Stub phase for integration tests

private struct StubPhase: ScanPhase {
    let id: String
    var displayName: String { id }
    let weight: Double
    let ips: [String]

    func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)
        for ip in ips {
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: ip,
                hostname: nil,
                vendor: nil,
                macAddress: nil,
                latency: nil,
                discoveredAt: .distantPast,
                source: .local
            ))
        }
        await onProgress(1.0)
    }
}
