import Testing
@testable import NetworkScanKit

struct RTTTrackerTests {

    @Test("starts with zero samples")
    func initialState() async {
        let tracker = RTTTracker()
        #expect(await tracker.sampleCount == 0)
    }

    @Test("returns base timeout before minSamples reached")
    func returnsBaseBeforeMinSamples() async {
        let tracker = RTTTracker(minSamples: 3, minTimeout: 100, maxTimeout: 1000)
        await tracker.recordRTT(50)
        await tracker.recordRTT(60)
        // Only 2 samples, minSamples is 3
        let timeout = await tracker.adaptiveTimeout(base: 500)
        #expect(timeout == 500)
    }

    @Test("sampleCount increments with each valid recording")
    func sampleCountIncrements() async {
        let tracker = RTTTracker()
        #expect(await tracker.sampleCount == 0)
        await tracker.recordRTT(100)
        #expect(await tracker.sampleCount == 1)
        await tracker.recordRTT(200)
        #expect(await tracker.sampleCount == 2)
    }

    @Test("zero RTT is ignored")
    func zeroRTTIgnored() async {
        let tracker = RTTTracker()
        await tracker.recordRTT(0)
        #expect(await tracker.sampleCount == 0)
        await tracker.recordRTT(-5)
        #expect(await tracker.sampleCount == 0)
    }

    @Test("returns adaptive timeout after enough samples")
    func returnsAdaptiveAfterMinSamples() async {
        let tracker = RTTTracker(minSamples: 3, minTimeout: 100, maxTimeout: 1000)
        await tracker.recordRTT(100)
        await tracker.recordRTT(100)
        await tracker.recordRTT(100)
        #expect(await tracker.sampleCount == 3)
        let timeout = await tracker.adaptiveTimeout(base: 500)
        // Should no longer return base (500); should return computed value
        #expect(timeout != 500)
        // Should be within [minTimeout, maxTimeout]
        #expect(timeout >= 100)
        #expect(timeout <= 1000)
    }

    @Test("adaptive timeout is clamped to minTimeout")
    func clampedToMinTimeout() async {
        // Very stable 5ms RTT → computed = srtt + 4*rttVar will be small
        let tracker = RTTTracker(minSamples: 1, minTimeout: 200, maxTimeout: 1000)
        await tracker.recordRTT(5)
        let timeout = await tracker.adaptiveTimeout(base: 500)
        // computed = 5 + 4*(5/2) = 5 + 10 = 15, clamped to 200
        #expect(timeout == 200)
    }

    @Test("adaptive timeout is clamped to maxTimeout")
    func clampedToMaxTimeout() async {
        // Very high RTT → computed would exceed maxTimeout
        let tracker = RTTTracker(minSamples: 1, minTimeout: 100, maxTimeout: 500)
        await tracker.recordRTT(1000)
        let timeout = await tracker.adaptiveTimeout(base: 300)
        // computed = 1000 + 4*(500) = 3000, clamped to 500
        #expect(timeout == 500)
    }

    @Test("custom minSamples threshold")
    func customMinSamples() async {
        let tracker = RTTTracker(minSamples: 1, minTimeout: 100, maxTimeout: 1000)
        await tracker.recordRTT(200)
        let timeout = await tracker.adaptiveTimeout(base: 500)
        // After 1 sample (minSamples=1), should be adaptive not base
        #expect(timeout != 500)
    }
}
