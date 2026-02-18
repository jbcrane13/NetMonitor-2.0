import Testing
@testable import NetworkScanKit

@Suite("ScanPipeline")
struct ScanPipelineTests {

    @Test("init stores steps")
    func initStoresSteps() {
        let step = ScanPipeline.Step(phases: [], concurrent: false)
        let pipeline = ScanPipeline(steps: [step])
        #expect(pipeline.steps.count == 1)
    }

    @Test("Step init stores phases and concurrent flag")
    func stepInit() {
        let step = ScanPipeline.Step(phases: [], concurrent: true)
        #expect(step.phases.isEmpty)
        #expect(step.concurrent == true)
    }

    @Test("Step non-concurrent flag")
    func stepNonConcurrent() {
        let step = ScanPipeline.Step(phases: [], concurrent: false)
        #expect(step.concurrent == false)
    }

    @Test("standard pipeline has 4 steps")
    func standardHasFourSteps() {
        let pipeline = ScanPipeline.standard()
        #expect(pipeline.steps.count == 4)
    }

    @Test("standard pipeline step 0 is concurrent with 2 phases")
    func standardStep0() {
        let pipeline = ScanPipeline.standard()
        let step = pipeline.steps[0]
        #expect(step.concurrent == true)
        #expect(step.phases.count == 2)
    }

    @Test("standard pipeline step 1 is concurrent with 2 phases")
    func standardStep1() {
        let pipeline = ScanPipeline.standard()
        let step = pipeline.steps[1]
        #expect(step.concurrent == true)
        #expect(step.phases.count == 2)
    }

    @Test("standard pipeline step 2 is sequential with 1 phase")
    func standardStep2() {
        let pipeline = ScanPipeline.standard()
        let step = pipeline.steps[2]
        #expect(step.concurrent == false)
        #expect(step.phases.count == 1)
    }

    @Test("standard pipeline step 3 is sequential with 1 phase")
    func standardStep3() {
        let pipeline = ScanPipeline.standard()
        let step = pipeline.steps[3]
        #expect(step.concurrent == false)
        #expect(step.phases.count == 1)
    }

    @Test("empty pipeline")
    func emptyPipeline() {
        let pipeline = ScanPipeline(steps: [])
        #expect(pipeline.steps.isEmpty)
    }
}
