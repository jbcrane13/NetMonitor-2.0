//
//  ContinuationTracker.swift
//  NetMonitor
//
//  Thread-safe tracker for ensuring continuations are resumed exactly once.
//

import Foundation

/// Thread-safe tracker for continuation safety in async/await patterns.
///
/// Use this when wrapping callback-based APIs with `withCheckedContinuation`
/// to ensure the continuation is resumed exactly once, even when multiple
/// code paths (success, failure, timeout) could trigger resumption.
///
/// Example:
/// ```swift
/// let tracker = ContinuationTracker()
/// return await withCheckedContinuation { continuation in
///     connection.stateUpdateHandler = { state in
///         switch state {
///         case .ready:
///             if tracker.tryResume() {
///                 continuation.resume(returning: true)
///             }
///         case .failed:
///             if tracker.tryResume() {
///                 continuation.resume(returning: false)
///             }
///         }
///     }
///     // Timeout handler
///     DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
///         if tracker.tryResume() {
///             continuation.resume(returning: false)
///         }
///     }
/// }
/// ```
final class ContinuationTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _hasResumed = false

    /// Whether the continuation has already been resumed.
    var hasResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _hasResumed
    }

    /// Attempts to mark as resumed.
    /// - Returns: `true` if this call set the flag (safe to resume), `false` if already resumed.
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _hasResumed { return false }
        _hasResumed = true
        return true
    }

    /// Resets the tracker for reuse.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _hasResumed = false
    }
}
