import Testing
@testable import NetMonitor_macOS

@Suite("ContinuationTracker")
struct ContinuationTrackerTests {

    @Test func initialStateIsNotResumed() {
        let tracker = ContinuationTracker()
        #expect(!tracker.hasResumed)
    }

    @Test func tryResumeReturnsTrueOnFirstCall() {
        let tracker = ContinuationTracker()
        #expect(tracker.tryResume())
    }

    @Test func hasResumedIsTrueAfterTryResume() {
        let tracker = ContinuationTracker()
        _ = tracker.tryResume()
        #expect(tracker.hasResumed)
    }

    @Test func tryResumeReturnsFalseOnSecondCall() {
        let tracker = ContinuationTracker()
        _ = tracker.tryResume()
        #expect(!tracker.tryResume())
    }

    @Test func multipleResumeCallsOnlyFirstReturnsTrue() {
        let tracker = ContinuationTracker()
        let first = tracker.tryResume()
        let second = tracker.tryResume()
        let third = tracker.tryResume()
        #expect(first)
        #expect(!second)
        #expect(!third)
    }

    @Test func resetClearsResumedFlag() {
        let tracker = ContinuationTracker()
        _ = tracker.tryResume()
        tracker.reset()
        #expect(!tracker.hasResumed)
    }

    @Test func tryResumeReturnsTrueAfterReset() {
        let tracker = ContinuationTracker()
        _ = tracker.tryResume()
        tracker.reset()
        #expect(tracker.tryResume())
    }

    @Test func resetWithoutPriorResumeHasNoEffect() {
        let tracker = ContinuationTracker()
        tracker.reset()
        #expect(!tracker.hasResumed)
    }

    @Test func resetAllowsSecondResume() {
        let tracker = ContinuationTracker()
        _ = tracker.tryResume()
        tracker.reset()
        _ = tracker.tryResume()
        #expect(tracker.hasResumed)
        #expect(!tracker.tryResume()) // third call should return false
    }

    @Test func concurrentResumesAllowExactlyOne() async {
        let tracker = ContinuationTracker()
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 {
                group.addTask { tracker.tryResume() }
            }
            var collected: [Bool] = []
            for await result in group { collected.append(result) }
            return collected
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(results.filter { !$0 }.count == 49)
    }
}

// MARK: - ContinuationTracker Extended Tests

@Suite("ContinuationTracker Extended")
struct ContinuationTrackerExtendedTests {

    @Test func concurrentRegistrationSafetyUnderHighContention() async {
        // Spawn 200 concurrent tasks all racing to be the first to resume.
        // Only exactly one must succeed regardless of concurrency level.
        let tracker = ContinuationTracker()
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<200 {
                group.addTask { tracker.tryResume() }
            }
            var collected: [Bool] = []
            for await result in group { collected.append(result) }
            return collected
        }
        let successCount = results.filter { $0 }.count
        let failureCount = results.filter { !$0 }.count
        #expect(successCount == 1)
        #expect(failureCount == 199)
        // The tracker must reflect resumed state after all tasks finish
        #expect(tracker.hasResumed)
    }

    @Test func repeatedResetAndResumeRemainsSafe() async {
        // Simulate a tracker being reused across multiple call cycles.
        let tracker = ContinuationTracker()
        for _ in 0..<10 {
            tracker.reset()
            let results = await withTaskGroup(of: Bool.self) { group in
                for _ in 0..<20 {
                    group.addTask { tracker.tryResume() }
                }
                var collected: [Bool] = []
                for await r in group { collected.append(r) }
                return collected
            }
            #expect(results.filter { $0 }.count == 1)
        }
    }
}
