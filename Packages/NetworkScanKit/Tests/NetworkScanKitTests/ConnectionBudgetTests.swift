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
}
