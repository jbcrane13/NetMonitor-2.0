import Foundation
import Testing
@testable import NetworkScanKit

@Suite("ScanEngine")
struct ScanEngineTests {

    @Test("scan executes sequential phases, reports progress, and returns sorted devices")
    func scanSequentialPipelineReportsProgressAndSortsResults() async {
        let engine = ScanEngine()
        let context = makeContext(hosts: ["192.168.1.20", "192.168.1.3"])
        let progress = ProgressRecorder()

        let phaseA = FixturePhase(
            id: "phase-a",
            displayName: "Phase A",
            weight: 1.0,
            progressValues: [0.0, 1.0],
            discoveredIPs: ["192.168.1.20"]
        )
        let phaseB = FixturePhase(
            id: "phase-b",
            displayName: "Phase B",
            weight: 3.0,
            progressValues: [0.5, 1.0],
            discoveredIPs: ["192.168.1.3"]
        )

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [phaseA], concurrent: false),
            ScanPipeline.Step(phases: [phaseB], concurrent: false)
        ])

        let results = await engine.scan(pipeline: pipeline, context: context) { value, name in
            await progress.record(value, phaseName: name)
        }

        #expect(results.map(\.ipAddress) == ["192.168.1.3", "192.168.1.20"])

        let updates = await progress.snapshot()
        #expect(!updates.isEmpty)
        #expect(updates.contains { $0.phaseName == "Phase A" })
        #expect(updates.contains { $0.phaseName == "Phase B" })
        #expect((updates.last?.value ?? 0) > 0.99)
    }

    @Test("scan executes every phase in concurrent step")
    func scanConcurrentStepExecutesAllPhases() async {
        let engine = ScanEngine()
        let context = makeContext(hosts: ["192.168.1.40", "192.168.1.50"])
        let progress = ProgressRecorder()

        let phaseA = FixturePhase(
            id: "concurrent-a",
            displayName: "Concurrent A",
            weight: 1.0,
            progressValues: [1.0],
            discoveredIPs: ["192.168.1.40"]
        )
        let phaseB = FixturePhase(
            id: "concurrent-b",
            displayName: "Concurrent B",
            weight: 1.0,
            progressValues: [1.0],
            discoveredIPs: ["192.168.1.50"]
        )

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [phaseA, phaseB], concurrent: true)
        ])

        let results = await engine.scan(pipeline: pipeline, context: context) { value, name in
            await progress.record(value, phaseName: name)
        }

        #expect(results.count == 2)
        #expect(Set(results.map(\.ipAddress)) == Set(["192.168.1.40", "192.168.1.50"]))

        let updates = await progress.snapshot()
        #expect(updates.contains { $0.phaseName == "Concurrent A" })
        #expect(updates.contains { $0.phaseName == "Concurrent B" })
    }

    @Test("zero-weight pipeline returns existing accumulator snapshot and skips phase execution")
    func scanWithZeroWeightPipelineSkipsPhases() async {
        let engine = ScanEngine()
        await engine.accumulator.upsert(makeDevice(ip: "10.0.0.10"))

        let zeroWeightPhase = FixturePhase(
            id: "zero-weight",
            displayName: "Zero Weight",
            weight: 0,
            progressValues: [1.0],
            discoveredIPs: ["10.0.0.20"]
        )

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [zeroWeightPhase], concurrent: false)
        ])

        let results = await engine.scan(pipeline: pipeline, context: makeContext(hosts: [])) { _, _ in
            // No-op
        }

        #expect(results.map(\.ipAddress) == ["10.0.0.10"])
    }

    @Test("reset clears accumulator after a scan")
    func resetClearsAccumulator() async {
        let engine = ScanEngine()
        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [
                FixturePhase(
                    id: "single",
                    displayName: "Single",
                    weight: 1.0,
                    progressValues: [1.0],
                    discoveredIPs: ["192.168.1.77"]
                )
            ], concurrent: false)
        ])

        _ = await engine.scan(pipeline: pipeline, context: makeContext(hosts: ["192.168.1.77"])) { _, _ in
            // No-op
        }
        #expect(await engine.accumulator.count == 1)

        await engine.reset()
        #expect(await engine.accumulator.count == 0)
    }

    private func makeContext(hosts: [String]) -> ScanContext {
        ScanContext(
            hosts: hosts,
            subnetFilter: { _ in true },
            localIP: nil
        )
    }

    private func makeDevice(ip: String) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip,
            hostname: nil,
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        )
    }
}

private struct FixturePhase: ScanPhase {
    let id: String
    let displayName: String
    let weight: Double
    let progressValues: [Double]
    let discoveredIPs: [String]

    func execute(
        context _: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        for value in progressValues {
            await onProgress(value)
        }

        for ip in discoveredIPs {
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: ip,
                hostname: nil,
                vendor: nil,
                macAddress: nil,
                latency: nil,
                discoveredAt: Date(),
                source: .local
            ))
        }
    }
}

private actor ProgressRecorder {
    struct Update: Sendable {
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
