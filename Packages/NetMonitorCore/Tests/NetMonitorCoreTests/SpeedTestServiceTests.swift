import Testing
@testable import NetMonitorCore

/// Tests for SpeedTestService state management and AtomicInt64 helper.
/// Network-dependent speed measurement (URLSession) is excluded.
struct SpeedTestServiceTests {

    // MARK: - Initial state

    @Test("initial downloadSpeed is 0")
    @MainActor
    func initialDownloadSpeedIsZero() {
        let service = SpeedTestService()
        #expect(service.downloadSpeed == 0)
    }

    @Test("initial uploadSpeed is 0")
    @MainActor
    func initialUploadSpeedIsZero() {
        let service = SpeedTestService()
        #expect(service.uploadSpeed == 0)
    }

    @Test("initial latency is 0")
    @MainActor
    func initialLatencyIsZero() {
        let service = SpeedTestService()
        #expect(service.latency == 0)
    }

    @Test("initial progress is 0")
    @MainActor
    func initialProgressIsZero() {
        let service = SpeedTestService()
        #expect(service.progress == 0)
    }

    @Test("initial phase is idle")
    @MainActor
    func initialPhaseIsIdle() {
        let service = SpeedTestService()
        #expect(service.phase == .idle)
    }

    @Test("initial isRunning is false")
    @MainActor
    func initialIsRunningIsFalse() {
        let service = SpeedTestService()
        #expect(service.isRunning == false)
    }

    @Test("initial errorMessage is nil")
    @MainActor
    func initialErrorMessageIsNil() {
        let service = SpeedTestService()
        #expect(service.errorMessage == nil)
    }

    @Test("default duration is 5.0 seconds")
    @MainActor
    func defaultDurationIs5Seconds() {
        let service = SpeedTestService()
        #expect(service.duration == 5.0)
    }

    // MARK: - stopTest() state reset

    @Test("stopTest() sets isRunning to false")
    @MainActor
    func stopTestSetsIsRunningFalse() {
        let service = SpeedTestService()
        service.stopTest()
        #expect(service.isRunning == false)
    }

    @Test("stopTest() sets phase to idle")
    @MainActor
    func stopTestSetsPhaseTool() {
        let service = SpeedTestService()
        service.stopTest()
        #expect(service.phase == .idle)
    }

    @Test("stopTest() is idempotent")
    @MainActor
    func stopTestIsIdempotent() {
        let service = SpeedTestService()
        service.stopTest()
        service.stopTest()
        #expect(service.phase == .idle)
        #expect(service.isRunning == false)
    }

    // MARK: - SpeedTestPhase ordering

    @Test("SpeedTestPhase idle rawValue is 'idle'")
    func speedTestPhaseIdleRawValue() {
        #expect(SpeedTestPhase.idle.rawValue == "idle")
    }

    @Test("SpeedTestPhase latency rawValue is 'latency'")
    func speedTestPhaseLatencyRawValue() {
        #expect(SpeedTestPhase.latency.rawValue == "latency")
    }

    @Test("SpeedTestPhase download rawValue is 'download'")
    func speedTestPhaseDownloadRawValue() {
        #expect(SpeedTestPhase.download.rawValue == "download")
    }

    @Test("SpeedTestPhase upload rawValue is 'upload'")
    func speedTestPhaseUploadRawValue() {
        #expect(SpeedTestPhase.upload.rawValue == "upload")
    }

    @Test("SpeedTestPhase complete rawValue is 'complete'")
    func speedTestPhaseCompleteRawValue() {
        #expect(SpeedTestPhase.complete.rawValue == "complete")
    }
}

// MARK: - AtomicInt64 Tests

struct AtomicInt64Tests {

    @Test("initial load returns 0")
    func initialLoadIsZero() {
        let counter = AtomicInt64()
        #expect(counter.load() == 0)
    }

    @Test("add positive delta increments value")
    func addPositiveDelta() {
        let counter = AtomicInt64()
        counter.add(100)
        #expect(counter.load() == 100)
    }

    @Test("add called multiple times accumulates correctly")
    func addMultipleTimesAccumulates() {
        let counter = AtomicInt64()
        counter.add(10)
        counter.add(20)
        counter.add(30)
        #expect(counter.load() == 60)
    }

    @Test("add negative delta decrements value")
    func addNegativeDelta() {
        let counter = AtomicInt64()
        counter.add(50)
        counter.add(-20)
        #expect(counter.load() == 30)
    }

    @Test("add zero does not change value")
    func addZeroDoesNotChange() {
        let counter = AtomicInt64()
        counter.add(42)
        counter.add(0)
        #expect(counter.load() == 42)
    }
}
