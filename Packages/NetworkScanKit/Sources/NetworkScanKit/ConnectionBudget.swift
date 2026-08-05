import Foundation
import os

private final class ConnectionWaiterState: @unchecked Sendable {
    private let isCancelledLock = OSAllocatedUnfairLock(initialState: false)

    var isCancelled: Bool {
        isCancelledLock.withLock { $0 }
    }

    func cancel() {
        isCancelledLock.withLock { $0 = true }
    }
}

/// Global connection budget that caps the number of concurrent NWConnections
/// across all services to prevent kernel socket exhaustion, reduce CPU heat,
/// and avoid GCD thread pool starvation.
///
/// Services must call ``acquire()`` before creating an NWConnection and
/// ``release()`` when the connection is cancelled or completes.
public actor ConnectionBudget {
    public static let shared = ConnectionBudget(limit: 60)

    private let limit: Int
    private var active = 0
    private struct Waiter {
        let id: UUID
        let state: ConnectionWaiterState
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var waiters: [Waiter] = []

    public init(limit: Int) {
        self.limit = limit
    }

    /// Effective limit factoring in device thermal state.
    private var effectiveLimit: Int {
        ThermalThrottleMonitor.shared.effectiveLimit(from: limit)
    }

    /// Wait until a connection slot is available, then claim it.
    @discardableResult
    public func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }

        if active < effectiveLimit {
            active += 1
            return true
        }

        let id = UUID()
        let waiterState = ConnectionWaiterState()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiters.append(Waiter(id: id, state: waiterState, continuation: continuation))
            }
        } onCancel: {
            waiterState.cancel()
            Task { await self.cancelWaiter(id: id) }
        }

        guard acquired, !Task.isCancelled else {
            if acquired {
                release()
            }
            return false
        }
        return true
    }

    /// Release a connection slot, waking the next waiter if any.
    ///
    /// Always resumes a waiter when slots are available, even if thermal
    /// throttling reduced `effectiveLimit` since the waiter was enqueued.
    /// This prevents deadlock when the thermal state changes mid-scan.
    public func release() {
        while !waiters.isEmpty {
            let next = waiters.removeFirst()
            guard !next.state.isCancelled else {
                next.continuation.resume(returning: false)
                continue
            }
            next.continuation.resume(returning: true)
            return
        }
        active = max(active - 1, 0)
    }

    /// Force-drain all waiters and reset the active count.
    /// Called when scan infrastructure detects a potential budget leak.
    public func reset() {
        active = 0
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.continuation.resume(returning: false)
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    /// Current number of active connections (for diagnostics).
    public var activeCount: Int { active }

    /// Current number of tasks waiting for a connection slot (for diagnostics).
    public var waitingCount: Int { waiters.count }
}
