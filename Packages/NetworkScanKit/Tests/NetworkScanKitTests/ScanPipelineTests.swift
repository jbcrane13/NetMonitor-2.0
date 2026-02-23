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
    
    // MARK: - forStrategy Factory Method Tests
    
    @Test("forStrategy .full returns pipeline with 4 steps")
    func forStrategyFullHasFourSteps() {
        let pipeline = ScanPipeline.forStrategy(.full)
        #expect(pipeline.steps.count == 4)
    }
    
    @Test("forStrategy .full matches standard pipeline")
    func forStrategyFullMatchesStandard() {
        let strategyPipeline = ScanPipeline.forStrategy(.full)
        let standardPipeline = ScanPipeline.standard()
        
        #expect(strategyPipeline.steps.count == standardPipeline.steps.count)
        
        for (index, (strategyStep, standardStep)) in zip(strategyPipeline.steps, standardPipeline.steps).enumerated() {
            #expect(strategyStep.concurrent == standardStep.concurrent, "Step \(index) concurrent mismatch")
            #expect(strategyStep.phases.count == standardStep.phases.count, "Step \(index) phase count mismatch")
        }
    }
    
    @Test("forStrategy .remote returns pipeline with 2 steps")
    func forStrategyRemoteHasTwoSteps() {
        let pipeline = ScanPipeline.forStrategy(.remote)
        #expect(pipeline.steps.count == 2)
    }
    
    @Test("forStrategy .remote step 0 has TCPProbeScanPhase only")
    func forStrategyRemoteStep0() {
        let pipeline = ScanPipeline.forStrategy(.remote)
        let step = pipeline.steps[0]
        #expect(step.concurrent == false)
        #expect(step.phases.count == 1)
        #expect(step.phases[0].id == "tcpProbe")
    }
    
    @Test("forStrategy .remote step 1 has ICMP and ReverseDNS concurrent")
    func forStrategyRemoteStep1() {
        let pipeline = ScanPipeline.forStrategy(.remote)
        let step = pipeline.steps[1]
        #expect(step.concurrent == true)
        #expect(step.phases.count == 2)
        
        let phaseIds = step.phases.map(\.id)
        #expect(phaseIds.contains("icmpLatency"))
        #expect(phaseIds.contains("reverseDNS"))
    }
    
    @Test("forStrategy .remote excludes ARP, Bonjour, and SSDP")
    func forStrategyRemoteExcludesLocalPhases() {
        let pipeline = ScanPipeline.forStrategy(.remote)
        let allPhaseIds = pipeline.steps.flatMap { $0.phases.map(\.id) }
        
        #expect(!allPhaseIds.contains("arp"))
        #expect(!allPhaseIds.contains("bonjour"))
        #expect(!allPhaseIds.contains("ssdp"))
    }
    
    @Test("forStrategy .full includes ARP, Bonjour, and SSDP")
    func forStrategyFullIncludesAllPhases() {
        let pipeline = ScanPipeline.forStrategy(.full)
        let allPhaseIds = pipeline.steps.flatMap { $0.phases.map(\.id) }
        
        #expect(allPhaseIds.contains("arp"))
        #expect(allPhaseIds.contains("bonjour"))
        #expect(allPhaseIds.contains("ssdp"))
        #expect(allPhaseIds.contains("tcpProbe"))
        #expect(allPhaseIds.contains("icmpLatency"))
        #expect(allPhaseIds.contains("reverseDNS"))
    }
}
