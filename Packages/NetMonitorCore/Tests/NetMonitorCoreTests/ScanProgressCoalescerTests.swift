import Testing
@testable import NetMonitorCore

struct ScanProgressCoalescerTests {
    @Test("publishes at most ten same-phase updates per second")
    func throttlesSamePhaseUpdates() {
        var coalescer = ScanProgressCoalescer(minimumInterval: 0.1)

        let first = coalescer.shouldPublish(progress: 0, phase: "TCP", timestamp: 1.0)
        let early = coalescer.shouldPublish(progress: 0.1, phase: "TCP", timestamp: 1.05)
        let afterInterval = coalescer.shouldPublish(progress: 0.2, phase: "TCP", timestamp: 1.1)

        #expect(first)
        #expect(!early)
        #expect(afterInterval)
    }

    @Test("phase transitions and completion publish immediately")
    func phaseAndCompletionBypassThrottle() {
        var coalescer = ScanProgressCoalescer(minimumInterval: 0.1)

        let first = coalescer.shouldPublish(progress: 0.1, phase: "ARP", timestamp: 1.0)
        let nextPhase = coalescer.shouldPublish(progress: 0.2, phase: "TCP", timestamp: 1.01)
        let completion = coalescer.shouldPublish(progress: 1, phase: "TCP", timestamp: 1.02)

        #expect(first)
        #expect(nextPhase)
        #expect(completion)
    }
}
