import Foundation
import Testing
@testable import NetworkScanKit

/// Coverage-focused tests for ScanPipeline, targeting the bonjour provider
/// parameters not exercised by existing tests.
@Suite("ScanPipeline coverage")
struct ScanPipelineCoverageTests {

    // MARK: - standard() with bonjour service provider

    @Test("standard() with bonjourServiceProvider preserves pipeline structure")
    func standardWithBonjourServiceProvider() {
        let services: @Sendable () async -> [BonjourServiceInfo] = {
            [BonjourServiceInfo(name: "Test", type: "_http._tcp", domain: "local.")]
        }
        let pipeline = ScanPipeline.standard(bonjourServiceProvider: services)

        // Structure should match standard pipeline
        #expect(pipeline.steps.count == 4)
        #expect(pipeline.steps[0].concurrent == true)
        #expect(pipeline.steps[0].phases.count == 2)
        #expect(pipeline.steps[1].concurrent == true)
        #expect(pipeline.steps[1].phases.count == 2)
        #expect(pipeline.steps[2].concurrent == false)
        #expect(pipeline.steps[2].phases.count == 1)
        #expect(pipeline.steps[3].concurrent == false)
        #expect(pipeline.steps[3].phases.count == 1)
    }

    @Test("standard() with bonjourStopProvider preserves pipeline structure")
    func standardWithBonjourStopProvider() {
        let stopCalled = LockedValue<Bool>(false)
        let stopProvider: @Sendable () async -> Void = {
            await stopCalled.setValue(true)
        }
        let pipeline = ScanPipeline.standard(bonjourStopProvider: stopProvider)

        #expect(pipeline.steps.count == 4)
        // Verify the stop provider is wired into the bonjour phase
        let bonjourPhase = pipeline.steps[0].phases.first { $0.id == "bonjour" }
        #expect(bonjourPhase != nil, "Step 0 should contain a bonjour phase")
    }

    @Test("standard() with both bonjour providers preserves pipeline structure")
    func standardWithBothProviders() {
        let services: @Sendable () async -> [BonjourServiceInfo] = {
            [BonjourServiceInfo(name: "Dev", type: "_ssh._tcp", domain: "local.")]
        }
        let stop: @Sendable () async -> Void = {}
        let pipeline = ScanPipeline.standard(
            bonjourServiceProvider: services,
            bonjourStopProvider: stop
        )

        #expect(pipeline.steps.count == 4)
        let allPhaseIds = pipeline.steps.flatMap { $0.phases.map(\.id) }
        #expect(allPhaseIds.contains("bonjour"))
    }

    // MARK: - Step properties

    @Test("Step with multiple phases stores all phases")
    func stepWithMultiplePhases() {
        let phaseA = SimpleTestPhase(id: "a", displayName: "A", weight: 1.0)
        let phaseB = SimpleTestPhase(id: "b", displayName: "B", weight: 2.0)
        let step = ScanPipeline.Step(phases: [phaseA, phaseB], concurrent: true)

        #expect(step.phases.count == 2)
        #expect(step.phases[0].id == "a")
        #expect(step.phases[1].id == "b")
        #expect(step.concurrent == true)
    }

    @Test("Step concurrent false with single phase")
    func stepConcurrentFalseSinglePhase() {
        let phase = SimpleTestPhase(id: "x", displayName: "X", weight: 5.0)
        let step = ScanPipeline.Step(phases: [phase], concurrent: false)

        #expect(step.phases.count == 1)
        #expect(step.concurrent == false)
    }

    // MARK: - Pipeline with custom steps

    @Test("custom pipeline with varying step configurations")
    func customPipelineWithVaryingSteps() {
        let p1 = SimpleTestPhase(id: "1", displayName: "One", weight: 1.0)
        let p2 = SimpleTestPhase(id: "2", displayName: "Two", weight: 2.0)
        let p3 = SimpleTestPhase(id: "3", displayName: "Three", weight: 3.0)
        let p4 = SimpleTestPhase(id: "4", displayName: "Four", weight: 4.0)
        let p5 = SimpleTestPhase(id: "5", displayName: "Five", weight: 5.0)

        let pipeline = ScanPipeline(steps: [
            ScanPipeline.Step(phases: [p1, p2, p3], concurrent: true),
            ScanPipeline.Step(phases: [p4], concurrent: false),
            ScanPipeline.Step(phases: [p5], concurrent: true),  // single phase, concurrent
        ])

        #expect(pipeline.steps.count == 3)
        #expect(pipeline.steps[0].phases.count == 3)
        #expect(pipeline.steps[0].concurrent == true)
        #expect(pipeline.steps[1].phases.count == 1)
        #expect(pipeline.steps[1].concurrent == false)
        #expect(pipeline.steps[2].phases.count == 1)
        #expect(pipeline.steps[2].concurrent == true)

        let totalWeight = pipeline.steps.flatMap(\.phases).reduce(0.0) { $0 + $1.weight }
        #expect(totalWeight == 15.0)
    }

    // MARK: - Phase IDs in standard pipeline

    @Test("standard pipeline phase display names are all non-empty")
    func standardPhaseDisplayNamesNonEmpty() {
        let pipeline = ScanPipeline.standard()
        for step in pipeline.steps {
            for phase in step.phases {
                #expect(!phase.displayName.isEmpty, "Phase \(phase.id) has empty displayName")
            }
        }
    }

    @Test("standard pipeline phase weights match expected values")
    func standardPhaseWeights() {
        let pipeline = ScanPipeline.standard()
        let weightsById = Dictionary(
            pipeline.steps.flatMap(\.phases).map { ($0.id, $0.weight) },
            uniquingKeysWith: { $1 }
        )
        #expect(weightsById["arp"] == 0.10)
        #expect(weightsById["bonjour"] == 0.13)
        #expect(weightsById["tcpProbe"] == 0.55)
        #expect(weightsById["ssdp"] == 0.06)
        #expect(weightsById["icmpLatency"] == 0.10)
        #expect(weightsById["reverseDNS"] == 0.08)
    }

    // MARK: - latencyPhase / trailingSteps (E5)

    @Test("standard() with default params keeps 4 steps and no trailing steps (iOS byte-identical)")
    func standardDefaultsHaveNoTrailingSteps() {
        let pipeline = ScanPipeline.standard()
        #expect(pipeline.steps.count == 4)
    }

    @Test("standard() substitutes a custom latencyPhase into step 2")
    func standardSubstitutesLatencyPhase() {
        let custom = SimpleTestPhase(id: "customLatency", displayName: "Custom", weight: 0.10)
        let pipeline = ScanPipeline.standard(latencyPhase: custom)
        #expect(pipeline.steps[2].phases.count == 1)
        #expect(pipeline.steps[2].phases[0].id == "customLatency")
    }

    @Test("standard() defaults latencyPhase to ICMPLatencyPhase")
    func standardDefaultsToICMPLatencyPhase() {
        let pipeline = ScanPipeline.standard()
        #expect(pipeline.steps[2].phases[0].id == "icmpLatency")
    }

    @Test("standard() appends trailingSteps after reverse DNS")
    func standardAppendsTrailingSteps() {
        let trailingPhase = SimpleTestPhase(id: "trailing", displayName: "Trailing", weight: 0.05)
        let trailing = ScanPipeline.Step(phases: [trailingPhase], concurrent: true)
        let pipeline = ScanPipeline.standard(trailingSteps: [trailing])

        #expect(pipeline.steps.count == 5)
        #expect(pipeline.steps[4].phases[0].id == "trailing")
        #expect(pipeline.steps[4].concurrent == true)
    }

    @Test("standard() supports multiple trailingSteps in order")
    func standardMultipleTrailingSteps() {
        let stepA = ScanPipeline.Step(phases: [SimpleTestPhase(id: "a", displayName: "A", weight: 1.0)], concurrent: false)
        let stepB = ScanPipeline.Step(phases: [SimpleTestPhase(id: "b", displayName: "B", weight: 1.0)], concurrent: false)
        let pipeline = ScanPipeline.standard(trailingSteps: [stepA, stepB])

        #expect(pipeline.steps.count == 6)
        #expect(pipeline.steps[4].phases[0].id == "a")
        #expect(pipeline.steps[5].phases[0].id == "b")
    }

    // MARK: - Pipeline mutability

    @Test("pipeline steps are mutable (var property)")
    func pipelineStepsMutable() {
        var pipeline = ScanPipeline(steps: [])
        #expect(pipeline.steps.isEmpty)

        let phase = SimpleTestPhase(id: "added", displayName: "Added", weight: 1.0)
        pipeline.steps = [ScanPipeline.Step(phases: [phase], concurrent: false)]
        #expect(pipeline.steps.count == 1)
        #expect(pipeline.steps[0].phases[0].id == "added")
    }
}

// MARK: - Simple test phase

private struct SimpleTestPhase: ScanPhase {
    let id: ScanPhaseID
    let displayName: String
    let weight: Double

    func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(1.0)
    }
}

// MARK: - Thread-safe value holder for testing

private actor LockedValue<T> {
    private var value: T
    init(_ value: T) { self.value = value }
    func setValue(_ newValue: T) { value = newValue }
    var getValue: T { value }
}
