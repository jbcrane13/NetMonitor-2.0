import Testing
@testable import NetworkScanKit

struct ConnectionBudgetTests {

    @Test("starts with zero active connections")
    func initialActiveCount() async {
        let budget = ConnectionBudget(limit: 5)
        #expect(await budget.activeCount == 0)
    }

    @Test("acquire increments active count")
    func acquireIncrementsCount() async {
        let budget = ConnectionBudget(limit: 5)
        await budget.acquire()
        #expect(await budget.activeCount == 1)
        await budget.acquire()
        #expect(await budget.activeCount == 2)
    }

    @Test("release decrements active count")
    func releaseDecrementsCount() async {
        let budget = ConnectionBudget(limit: 5)
        await budget.acquire()
        await budget.acquire()
        #expect(await budget.activeCount == 2)
        await budget.release()
        #expect(await budget.activeCount == 1)
        await budget.release()
        #expect(await budget.activeCount == 0)
    }

    @Test("release does not go below zero")
    func releaseDoesNotGoBelowZero() async {
        let budget = ConnectionBudget(limit: 5)
        await budget.release()  // release without prior acquire
        #expect(await budget.activeCount == 0)
    }

    @Test("reset clears active count")
    func resetClearsActiveCount() async {
        let budget = ConnectionBudget(limit: 10)
        await budget.acquire()
        await budget.acquire()
        await budget.acquire()
        #expect(await budget.activeCount == 3)
        await budget.reset()
        #expect(await budget.activeCount == 0)
    }

    @Test("reset drains waiters unblocking pending acquires")
    func resetDrainsWaiters() async throws {
        let budget = ConnectionBudget(limit: 1)
        await budget.acquire()  // fills the slot

        // This task will block until reset() releases the slot
        let pending = Task {
            await budget.acquire()
        }

        while await budget.waitingCount == 0 {
            await Task.yield()
        }

        await budget.reset()
        let acquired = await pending.value

        #expect(!acquired)
        #expect(await budget.activeCount == 0)
    }

    @Test("cancelling a waiter does not consume a connection slot")
    func cancellationRemovesWaiter() async {
        let budget = ConnectionBudget(limit: 1)
        #expect(await budget.acquire())

        let pending = Task {
            await budget.acquire()
        }
        while await budget.waitingCount == 0 {
            await Task.yield()
        }

        pending.cancel()

        #expect(await pending.value == false)
        #expect(await budget.waitingCount == 0)
        #expect(await budget.activeCount == 1)

        await budget.release()
        #expect(await budget.activeCount == 0)
    }

    @Test("acquire and release at limit boundary")
    func atLimitBoundary() async throws {
        let budget = ConnectionBudget(limit: 3)
        await budget.acquire()
        await budget.acquire()
        await budget.acquire()
        #expect(await budget.activeCount == 3)
        await budget.release()
        // One slot freed; attempt to acquire again should succeed
        let task = Task {
            await budget.acquire()
        }
        #expect(await task.value)
        #expect(await budget.activeCount == 3)
    }

    @Test("custom limit respected")
    func customLimit() async {
        let budget = ConnectionBudget(limit: 100)
        for _ in 0..<100 {
            await budget.acquire()
        }
        #expect(await budget.activeCount == 100)
    }

    // MARK: - withConnectionSlot

    @Test("withConnectionSlot runs the body and returns the active count to zero")
    func withConnectionSlotRunsBodyAndReleases() async {
        let budget = ConnectionBudget(limit: 5)

        let result = await withConnectionSlot(budget: budget) { () async -> Int in
            await budget.activeCount
        }

        #expect(result == 1)
        #expect(await budget.activeCount == 0)
    }

    @Test("cancelling the task mid-body still releases the slot with no unstructured task")
    func withConnectionSlotCancellationReleases() async {
        let budget = ConnectionBudget(limit: 1)

        let task = Task {
            await withConnectionSlot(budget: budget) { () async -> Int in
                while !Task.isCancelled {
                    await Task.yield()
                }
                return 42
            }
        }

        while await budget.activeCount == 0 {
            await Task.yield()
        }

        task.cancel()
        let result = await task.value

        // The body returned cooperatively after observing cancellation, and by the
        // time the task's value is available the slot has already been released —
        // no detached/unstructured Task delays the release past this await.
        #expect(result == 42)
        #expect(await budget.activeCount == 0)
    }

    @Test("reset during a wait yields nil from withConnectionSlot")
    func withConnectionSlotResetDuringWaitYieldsNil() async {
        let budget = ConnectionBudget(limit: 1)
        #expect(await budget.acquire()) // fill the only slot

        let waitingTask = Task {
            await withConnectionSlot(budget: budget) { 99 }
        }

        while await budget.waitingCount == 0 {
            await Task.yield()
        }

        await budget.reset()

        let result = await waitingTask.value
        #expect(result == nil)
        #expect(await budget.activeCount == 0)
    }

    @Test("100 concurrent withConnectionSlot calls never observe activeCount above the limit")
    func withConnectionSlotRespectsLimitUnderConcurrency() async {
        let budget = ConnectionBudget(limit: 5)

        actor OverflowObserver {
            private(set) var sawOverflow = false
            func record(_ active: Int, limit: Int) {
                if active > limit {
                    sawOverflow = true
                }
            }
        }
        let observer = OverflowObserver()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    _ = await withConnectionSlot(budget: budget) { () async -> Int in
                        let active = await budget.activeCount
                        await observer.record(active, limit: 5)
                        await Task.yield()
                        return active
                    }
                }
            }
        }

        #expect(await observer.sawOverflow == false)
        #expect(await budget.activeCount == 0)
    }
}
