import Testing
import Foundation
@testable import NetworkScanKit

struct ConcurrencyTests {

    private actor ConcurrencyTracker {
        private var active = 0
        private var maxObserved = 0
        private(set) var results: [Int] = []

        func enter() {
            active += 1
            maxObserved = max(maxObserved, active)
        }

        func exit() {
            active -= 1
        }

        func record(_ value: Int) {
            results.append(value)
        }

        var observedMax: Int { maxObserved }
    }

    @Test("forEachBounded never exceeds the concurrency limit")
    func neverExceedsLimit() async {
        let tracker = ConcurrencyTracker()
        let items = Array(0..<20)

        await forEachBounded(items, limit: 3, operation: { item -> Int in
            await tracker.enter()
            try? await Task.sleep(for: .milliseconds(5))
            await tracker.exit()
            return item
        }, onResult: { _ in })

        #expect(await tracker.observedMax <= 3)
    }

    @Test("forEachBounded delivers every result exactly once")
    func deliversEveryResult() async {
        let items = Array(0..<25)
        actor Collector {
            var seen: [Int] = []
            func add(_ value: Int) { seen.append(value) }
        }
        let collector = Collector()

        await forEachBounded(items, limit: 4, operation: { item in
            item * 2
        }, onResult: { result in
            await collector.add(result)
        })

        let seen = await collector.seen
        #expect(seen.sorted() == items.map { $0 * 2 }.sorted())
        #expect(seen.count == items.count)
    }

    @Test("forEachBounded with an empty sequence calls onResult zero times")
    func emptySequenceNoResults() async {
        var callCount = 0
        await forEachBounded([Int](), limit: 5, operation: { item in
            item
        }, onResult: { _ in
            callCount += 1
        })
        #expect(callCount == 0)
    }

    @Test("forEachBounded with limit larger than item count still processes all items")
    func limitLargerThanItemCount() async {
        let items = [1, 2, 3]
        var seen: Set<Int> = []
        await forEachBounded(items, limit: 100, operation: { $0 }, onResult: { result in
            seen.insert(result)
        })
        #expect(seen == Set(items))
    }

    @Test("forEachBounded onResult can mutate caller-local state safely (non-Sendable closure)")
    func onResultMutatesLocalState() async {
        var total = 0
        await forEachBounded(Array(1...10), limit: 3, operation: { $0 }, onResult: { value in
            total += value
        })
        #expect(total == 55)
    }
}
