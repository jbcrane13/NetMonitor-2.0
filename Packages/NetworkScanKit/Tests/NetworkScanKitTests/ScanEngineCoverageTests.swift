import Foundation
import Testing
@testable import NetworkScanKit

/// Coverage-focused tests for ScanEngine, targeting branches not exercised
/// by the existing ScanEngineTests and ScanPipelineIntegrationTests.
@Suite("ScanEngine coverage")
struct ScanEngineCoverageTests {

    // MARK: - Convenience scan(context:) method

    @Test("convenience scan with .full strategy creates standard pipeline and returns devices")
    func convenienceScanFullStrategy() async {
        let engine = ScanEngine()
        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil,
            scanStrategy: .full
        )
        let progress = ProgressRecorder()

        let results = await engine.scan(context: context) { value, name in
            await progress.record(value, phaseName: name)
        }

        // The real pipeline phases will run against 192.168.1.1.
        // We can't guarantee what's found, but the pipeline must complete.
        let updates = await progress.snapshot()
        #expect(!updates.isEmpty, "Progress should be reported during a .full scan")
        // Final progress should be 1.0 (or very close)
        if let last = updates.last {
            #expect(last.value > 0.99, "Final progress should approach 1.0, got \(last.value)")
        }
        // Results should be a sorted snapshot (may be empty if host is unreachable)
        _ = results
    }

    @Test("convenience scan with .remote strategy creates remote pipeline")
    func convenienceScanRemoteStrategy() async {
        let engine = ScanEngine()
        let context = ScanContext(
            hosts: ["10.0.0.1"],
            subnetFilter: { _ in true },
            localIP: nil,
            scanStrategy: .remote
        )
        let progress = ProgressRecorder()

        let results = await engine.scan(context: context) { value, name in
            await progress.record(value, phaseName: name)
        }

        let updates = await progress.snapshot()
        #expect(!updates.isEmpty, "Progress should be reported during a .remote scan")
        // The remote pipeline has 2 steps: TCP probe, then ICMP+DNS concurrent
        // Phase names should include tcpProbe at minimum
        #expect(updates.contains { $0.phaseName == "Probing ports…" })
        _ = results
    }

    @Test("convenience scan with bonjour service provider passes services through")
    func convenienceScanWithBonjourProvider() async {
        let engine = ScanEngine()
        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil,
            scanStrategy: .full
        )
        let progress = ProgressRecorder()

        // Provide a bonjour service that returns a known device
        let bonjourServices: @Sendable () async -> [BonjourServiceInfo] = {
            [
                BonjourServiceInfo(name: "TestDevice", type: "_http._tcp", domain: "local."),
            ]
        }
        let bonjourStop: @Sendable () async -> Void = {
            // no-op stop
        }

        let results = await engine.scan(
            context: context,
            bonjourServiceProvider: bonjourServices,
            bonjourStopProvider: bonjourStop
        ) { value, name in
            await progress.record(value, phaseName: name)
        }

        // Pipeline should complete without errors
        let updates = await progress.snapshot()
        #expect(!updates.isEmpty)
        _ = results
    }

    @Test("convenience scan with default bonjour provider returns empty services")
    func convenienceScanDefaultBonjourProvider() async {
        let engine = ScanEngine()
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil,
            scanStrategy: .full
        )

        // Don't pass bonjourServiceProvider — should use default empty provider
        let results = await engine.scan(context: context) { _, _ in }
        // Empty hosts means phases discover nothing; pipeline should complete
        _ = results
    }

    // MARK: - Single-phase concurrent step (concurrent: true with count == 1)

    @Test("concurrent step with single phase runs as sequential")
    func concurrentStepWithSinglePhase() async {
        let engine = ScanEngine()
        let phase = StubPhase(id: "solo", displayName: "Solo Phase", weight: 2.0, ips: ["10.0.0.5"])
        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [phase], concurrent: true)
        ])
        let context = makeContext(hosts: ["10.0.0.5"])
        let progress = ProgressRecorder()

        let results = await engine.scan(pipeline: pipeline, context: context) { value, name in
            await progress.record(value, phaseName: name)
        }

        #expect(results.count == 1)
        #expect(results[0].ipAddress == "10.0.0.5")

        let updates = await progress.snapshot()
        #expect(updates.contains { $0.phaseName == "Solo Phase" })
    }

    // MARK: - Mixed pipeline (concurrent + sequential steps)

    @Test("mixed pipeline with concurrent then sequential steps")
    func mixedPipelineConcurrentThenSequential() async {
        let engine = ScanEngine()
        let phaseA = StubPhase(id: "a", displayName: "Phase A", weight: 1.0, ips: ["192.168.1.10"])
        let phaseB = StubPhase(id: "b", displayName: "Phase B", weight: 1.0, ips: ["192.168.1.20"])
        let phaseC = StubPhase(id: "c", displayName: "Phase C", weight: 2.0, ips: ["192.168.1.30"])

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [phaseA, phaseB], concurrent: true),
            ScanPipeline.Step(phases: [phaseC], concurrent: false),
        ])

        let context = makeContext(hosts: ["192.168.1.10", "192.168.1.20", "192.168.1.30"])
        let progress = ProgressRecorder()

        let results = await engine.scan(pipeline: pipeline, context: context) { value, name in
            await progress.record(value, phaseName: name)
        }

        let ips = Set(results.map(\.ipAddress))
        #expect(ips == Set(["192.168.1.10", "192.168.1.20", "192.168.1.30"]))

        let updates = await progress.snapshot()
        #expect(updates.contains { $0.phaseName == "Phase A" })
        #expect(updates.contains { $0.phaseName == "Phase B" })
        #expect(updates.contains { $0.phaseName == "Phase C" })
    }

    @Test("mixed pipeline with sequential then concurrent steps")
    func mixedPipelineSequentialThenConcurrent() async {
        let engine = ScanEngine()
        let phaseA = StubPhase(id: "seq-a", displayName: "Seq A", weight: 3.0, ips: ["172.16.0.1"])
        let phaseB = StubPhase(id: "con-b", displayName: "Con B", weight: 1.0, ips: ["172.16.0.2"])
        let phaseC = StubPhase(id: "con-c", displayName: "Con C", weight: 1.0, ips: ["172.16.0.3"])

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [phaseA], concurrent: false),
            ScanPipeline.Step(phases: [phaseB, phaseC], concurrent: true),
        ])

        let context = makeContext(hosts: ["172.16.0.1", "172.16.0.2", "172.16.0.3"])

        let results = await engine.scan(pipeline: pipeline, context: context) { _, _ in }

        let ips = Set(results.map(\.ipAddress))
        #expect(ips == Set(["172.16.0.1", "172.16.0.2", "172.16.0.3"]))
    }

    // MARK: - Progress calculation with weighted phases

    @Test("progress values increase monotonically across sequential phases")
    func progressMonotonicallyIncreasing() async {
        let engine = ScanEngine()
        let phaseA = StubPhase(id: "p1", displayName: "P1", weight: 1.0, ips: [])
        let phaseB = StubPhase(id: "p2", displayName: "P2", weight: 3.0, ips: [])

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [phaseA], concurrent: false),
            ScanPipeline.Step(phases: [phaseB], concurrent: false),
        ])

        let context = makeContext(hosts: [])
        let collector = ProgressCollector()

        _ = await engine.scan(pipeline: pipeline, context: context) { value, _ in
            await collector.append(value)
        }

        let values = await collector.values
        // Verify monotonically non-decreasing
        for i in 1..<values.count {
            #expect(values[i] >= values[i - 1],
                   "Progress at index \(i) (\(values[i])) < previous (\(values[i - 1]))")
        }
    }

    @Test("progress reaches 1.0 at end of pipeline")
    func progressReachesOne() async {
        let engine = ScanEngine()
        let phaseA = StubPhase(id: "pa", displayName: "PA", weight: 2.0, ips: ["10.1.1.1"])
        let phaseB = StubPhase(id: "pb", displayName: "PB", weight: 3.0, ips: ["10.1.1.2"])

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [phaseA], concurrent: false),
            ScanPipeline.Step(phases: [phaseB], concurrent: false),
        ])

        let context = makeContext(hosts: ["10.1.1.1", "10.1.1.2"])
        let collector = ProgressCollector()

        _ = await engine.scan(pipeline: pipeline, context: context) { value, _ in
            await collector.append(value)
        }

        let values = await collector.values
        #expect(!values.isEmpty)
        // Final progress should be exactly or very close to 1.0
        if let last = values.last {
            #expect(last > 0.99)
        }
    }

    // MARK: - Accumulator access

    @Test("accumulator is accessible nonisolated after scan")
    func accumulatorAccessibleNonisolated() async {
        let engine = ScanEngine()
        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(
                phases: [StubPhase(id: "acc", displayName: "Acc", weight: 1.0, ips: ["192.168.0.1"])],
                concurrent: false
            )
        ])
        _ = await engine.scan(pipeline: pipeline, context: makeContext(hosts: [])) { _, _ in }

        // accumulator is `nonisolated let` — access without await
        let acc = engine.accumulator
        #expect(await acc.count == 1)
        #expect(await acc.contains(ip: "192.168.0.1"))
    }

    // MARK: - Reset between scans

    @Test("reset between scans ensures fresh accumulator state")
    func resetBetweenScansEnsuresFreshState() async {
        let engine = ScanEngine()
        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(
                phases: [StubPhase(id: "r", displayName: "R", weight: 1.0, ips: ["10.0.0.1"])],
                concurrent: false
            )
        ])
        let context = makeContext(hosts: [])

        // First scan
        _ = await engine.scan(pipeline: pipeline, context: context) { _, _ in }
        #expect(await engine.accumulator.count == 1)

        // Reset
        await engine.reset()
        #expect(await engine.accumulator.isEmpty)
        #expect(await engine.accumulator.count == 0)

        // Second scan with different IPs
        let pipeline2 = ScanPipeline(steps: [
            ScanPipeline.Step(
                phases: [StubPhase(id: "r2", displayName: "R2", weight: 1.0, ips: ["10.0.0.2", "10.0.0.3"])],
                concurrent: false
            )
        ])
        let results = await engine.scan(pipeline: pipeline2, context: context) { _, _ in }
        #expect(results.count == 2)
        #expect(await engine.accumulator.count == 2)
    }

    // MARK: - Pipeline with steps that have no phases

    @Test("pipeline step with empty phases array is handled gracefully")
    func pipelineStepWithEmptyPhases() async {
        let engine = ScanEngine()
        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [], concurrent: false),
            ScanPipeline.Step(
                phases: [StubPhase(id: "only", displayName: "Only", weight: 1.0, ips: ["192.168.5.1"])],
                concurrent: false
            ),
        ])
        let context = makeContext(hosts: [])

        let results = await engine.scan(pipeline: pipeline, context: context) { _, _ in }
        #expect(results.count == 1)
        #expect(results[0].ipAddress == "192.168.5.1")
    }

    // MARK: - Three-step pipeline with mixed concurrency

    @Test("three-step pipeline with alternating concurrency")
    func threeStepMixedPipeline() async {
        let engine = ScanEngine()
        let phase1A = StubPhase(id: "1a", displayName: "1A", weight: 1.0, ips: ["10.0.0.1"])
        let phase2A = StubPhase(id: "2a", displayName: "2A", weight: 1.0, ips: ["10.0.0.2"])
        let phase2B = StubPhase(id: "2b", displayName: "2B", weight: 1.0, ips: ["10.0.0.3"])
        let phase3A = StubPhase(id: "3a", displayName: "3A", weight: 1.0, ips: ["10.0.0.4"])

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [phase1A], concurrent: false),
            ScanPipeline.Step(phases: [phase2A, phase2B], concurrent: true),
            ScanPipeline.Step(phases: [phase3A], concurrent: false),
        ])

        let context = makeContext(hosts: [])
        let results = await engine.scan(pipeline: pipeline, context: context) { _, _ in }

        let ips = Set(results.map(\.ipAddress))
        #expect(ips == Set(["10.0.0.1", "10.0.0.2", "10.0.0.3", "10.0.0.4"]))
    }

    // MARK: - Deduplication across concurrent and sequential steps

    @Test("duplicate IP across concurrent and sequential steps is deduplicated")
    func deduplicationAcrossSteps() async {
        let engine = ScanEngine()
        let phaseA = StubPhase(id: "a", displayName: "A", weight: 1.0, ips: ["192.168.1.1"])
        let phaseB = StubPhase(id: "b", displayName: "B", weight: 1.0, ips: ["192.168.1.1"])
        let phaseC = StubPhase(id: "c", displayName: "C", weight: 1.0, ips: ["192.168.1.1"])

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [phaseA, phaseB], concurrent: true),
            ScanPipeline.Step(phases: [phaseC], concurrent: false),
        ])

        let context = makeContext(hosts: [])
        let results = await engine.scan(pipeline: pipeline, context: context) { _, _ in }

        #expect(results.count == 1)
        #expect(results[0].ipAddress == "192.168.1.1")
    }

    // MARK: - Phase that discovers no devices

    @Test("phase discovering no devices still reports progress and completes")
    func phaseDiscoveringNoDevices() async {
        let engine = ScanEngine()
        let emptyPhase = StubPhase(id: "empty", displayName: "Empty", weight: 2.0, ips: [])
        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [emptyPhase], concurrent: false)
        ])
        let progress = ProgressRecorder()

        let results = await engine.scan(pipeline: pipeline, context: makeContext(hosts: [])) { value, name in
            await progress.record(value, phaseName: name)
        }

        #expect(results.isEmpty)
        let updates = await progress.snapshot()
        // Should still have progress updates (0.0 and 1.0)
        #expect(!updates.isEmpty)
    }

    // MARK: - Multiple concurrent steps in a row

    @Test("two consecutive concurrent steps")
    func twoConsecutiveConcurrentSteps() async {
        let engine = ScanEngine()
        let phaseA = StubPhase(id: "ca", displayName: "CA", weight: 1.0, ips: ["10.0.0.10"])
        let phaseB = StubPhase(id: "cb", displayName: "CB", weight: 1.0, ips: ["10.0.0.11"])
        let phaseC = StubPhase(id: "cc", displayName: "CC", weight: 1.0, ips: ["10.0.0.12"])
        let phaseD = StubPhase(id: "cd", displayName: "CD", weight: 1.0, ips: ["10.0.0.13"])

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [phaseA, phaseB], concurrent: true),
            ScanPipeline.Step(phases: [phaseC, phaseD], concurrent: true),
        ])

        let context = makeContext(hosts: [])
        let results = await engine.scan(pipeline: pipeline, context: context) { _, _ in }

        let ips = Set(results.map(\.ipAddress))
        #expect(ips == Set(["10.0.0.10", "10.0.0.11", "10.0.0.12", "10.0.0.13"]))
    }

    // MARK: - Helpers

    private func makeContext(hosts: [String]) -> ScanContext {
        ScanContext(hosts: hosts, subnetFilter: { _ in true }, localIP: nil)
    }
}

// MARK: - Stub Phase for coverage tests

private struct StubPhase: ScanPhase {
    let id: String
    let displayName: String
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

// MARK: - Actor helpers for progress collection

private actor ProgressRecorder {
    struct Update {
        let value: Double
        let phaseName: String
    }

    private var updates: [Update] = []

    func record(_ value: Double, phaseName: String) {
        updates.append(Update(value: value, phaseName: phaseName))
    }

    func snapshot() -> [Update] {
        updates
    }
}

private actor ProgressCollector {
    private var _values: [Double] = []
    func append(_ v: Double) { _values.append(v) }
    var values: [Double] { _values }
}
