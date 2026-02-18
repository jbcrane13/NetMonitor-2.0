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
