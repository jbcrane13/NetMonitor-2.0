import Foundation

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
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int) {
        self.limit = limit
    }

    /// Effective limit factoring in device thermal state.
    private var effectiveLimit: Int {
        ThermalThrottleMonitor.shared.effectiveLimit(from: limit)
    }

    /// Wait until a connection slot is available, then claim it.
    public func acquire() async {
        if active < effectiveLimit {
            active += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
        active += 1
    }

    /// Release a connection slot, waking the next waiter if any.
    ///
    /// Always resumes a waiter when slots are available, even if thermal
    /// throttling reduced `effectiveLimit` since the waiter was enqueued.
    /// This prevents deadlock when the thermal state changes mid-scan.
    public func release() {
        active = max(active - 1, 0)
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        }
    }

    /// Force-drain all waiters and reset the active count.
    /// Called when scan infrastructure detects a potential budget leak.
    public func reset() {
        active = 0
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    /// Current number of active connections (for diagnostics).
    public var activeCount: Int { active }
}
