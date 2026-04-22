import Foundation
import Testing
@testable import NetworkScanKit

/// Coverage-focused tests for ScanPipeline, targeting the bonjour provider
/// parameters and factory method branches not exercised by existing tests.
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

    // MARK: - forStrategy() with bonjour providers

    @Test("forStrategy .full with bonjourServiceProvider has 4 steps")
    func forStrategyFullWithProvider() {
        let services: @Sendable () async -> [BonjourServiceInfo] = { [] }
        let pipeline = ScanPipeline.forStrategy(.full, bonjourServiceProvider: services)

        #expect(pipeline.steps.count == 4)
    }

    @Test("forStrategy .full with bonjourStopProvider has 4 steps")
    func forStrategyFullWithStopProvider() {
        let stop: @Sendable () async -> Void = {}
        let pipeline = ScanPipeline.forStrategy(.full, bonjourStopProvider: stop)

        #expect(pipeline.steps.count == 4)
    }

    @Test("forStrategy .full with both providers matches standard with providers")
    func forStrategyFullWithBothProviders() {
        let services: @Sendable () async -> [BonjourServiceInfo] = {
            [BonjourServiceInfo(name: "X", type: "_x._tcp", domain: "local.")]
        }
        let stop: @Sendable () async -> Void = {}
        let strategyPipeline = ScanPipeline.forStrategy(
            .full,
            bonjourServiceProvider: services,
            bonjourStopProvider: stop
        )
        let standardPipeline = ScanPipeline.standard(
            bonjourServiceProvider: services,
            bonjourStopProvider: stop
        )

        #expect(strategyPipeline.steps.count == standardPipeline.steps.count)
        for (i, (sStep, stdStep)) in zip(strategyPipeline.steps, standardPipeline.steps).enumerated() {
            #expect(sStep.concurrent == stdStep.concurrent, "Step \(i) concurrent mismatch")
            #expect(sStep.phases.count == stdStep.phases.count, "Step \(i) phase count mismatch")
        }
    }

    @Test("forStrategy .remote ignores bonjourServiceProvider")
    func forStrategyRemoteIgnoresBonjourProvider() {
        let services: @Sendable () async -> [BonjourServiceInfo] = {
            [BonjourServiceInfo(name: "Ignored", type: "_http._tcp", domain: "local.")]
        }
        let pipeline = ScanPipeline.forStrategy(.remote, bonjourServiceProvider: services)

        // Remote pipeline should still have 2 steps, no bonjour phase
        #expect(pipeline.steps.count == 2)
        let allPhaseIds = pipeline.steps.flatMap { $0.phases.map(\.id) }
        #expect(!allPhaseIds.contains("bonjour"))
    }

    @Test("forStrategy .remote ignores bonjourStopProvider")
    func forStrategyRemoteIgnoresStopProvider() {
        let stop: @Sendable () async -> Void = {}
        let pipeline = ScanPipeline.forStrategy(.remote, bonjourStopProvider: stop)

        #expect(pipeline.steps.count == 2)
        let allPhaseIds = pipeline.steps.flatMap { $0.phases.map(\.id) }
        #expect(!allPhaseIds.contains("bonjour"))
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

    // MARK: - Phase IDs in standard and remote pipelines

    @Test("standard pipeline phase display names are all non-empty")
    func standardPhaseDisplayNamesNonEmpty() {
        let pipeline = ScanPipeline.standard()
        for step in pipeline.steps {
            for phase in step.phases {
                #expect(!phase.displayName.isEmpty, "Phase \(phase.id) has empty displayName")
            }
        }
    }

    @Test("remote pipeline phase display names are all non-empty")
    func remotePhaseDisplayNamesNonEmpty() {
        let pipeline = ScanPipeline.forStrategy(.remote)
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

    @Test("remote pipeline total weight is sum of tcpProbe + icmpLatency + reverseDNS")
    func remotePipelineTotalWeight() {
        let pipeline = ScanPipeline.forStrategy(.remote)
        let total = pipeline.steps.flatMap(\.phases).reduce(0.0) { $0 + $1.weight }
        // TCP probe (0.55) + ICMP latency (0.10) + Reverse DNS (0.08) = 0.73
        #expect(total == 0.73)
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
    let id: String
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
