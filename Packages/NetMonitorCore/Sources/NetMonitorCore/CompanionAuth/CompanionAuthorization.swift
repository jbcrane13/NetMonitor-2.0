import Foundation
import Synchronization

/// One companion link's submission lock (#590). Submitting work for the link (asking the model)
/// and closing the link both take it, so they never overlap: a close waits for a submission
/// already inside, and no submission starts after a close returns.
public final class CompanionSubmissionLock: Sendable {
    private struct State {
        var isOpen = true
        /// Work started for the link (#586): each one's cancel, called when the link closes.
        var operations: [UUID: @Sendable () -> Void] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    public var isOpen: Bool {
        state.withLock { $0.isOpen }
    }

    /// Closes the link for submissions, after any submission in progress has finished, and
    /// cancels the work started for it.
    public func close() {
        let operations = state.withLock { state in
            state.isOpen = false
            let operations = Array(state.operations.values)
            state.operations = [:]
            return operations
        }
        operations.forEach { $0() }
    }

    /// Runs `body` only while the link is open and `isAuthorized` holds, with both checks and
    /// `body` inside one critical section that `close` can't interleave with.
    func perform<T: Sendable>(isAuthorized: () -> Bool, _ body: () -> T) -> T? {
        state.withLock { state in
            guard state.isOpen, isAuthorized() else { return nil }
            return body()
        }
    }

    /// Like `perform`, and the task `body` makes is registered with the link in the same critical
    /// section: a close from then on cancels it. The task ends its registration with `end(_:)`.
    func start<Success: Sendable>(isAuthorized: () -> Bool, _ body: (UUID) -> Task<Success, Never>) -> Task<Success, Never>? {
        state.withLock { state in
            guard state.isOpen, isAuthorized() else { return nil }
            let id = UUID()
            let task = body(id)
            state.operations[id] = { task.cancel() }
            return task
        }
    }

    func end(_ id: UUID) {
        _ = state.withLock { $0.operations.removeValue(forKey: id) }
    }
}

/// Whether the companion link a request came in on is still authorised (#590): bound to that
/// link's submission lock and credential generation, so a revoke or a close turns it false.
///
/// Work for a phone checks `isCurrent()` after every suspension. The model is asked only through
/// `perform(_:)`, which checks and submits inside the link's lock, or through `start(_:)`, which
/// registers its task with the lock in the same step; the Mac's Remove closes that lock before it
/// revokes the phone's key, so a revoke either comes before the submission (the model is never
/// asked) or after it (closing the link then cancels the registered work, which stops it).
public struct CompanionAuthorization: Sendable {
    private let lock: CompanionSubmissionLock
    private let check: @Sendable () -> Bool

    public init(lock: CompanionSubmissionLock, _ check: @escaping @Sendable () -> Bool) {
        self.lock = lock
        self.check = check
    }

    /// A token with its own lock, for a check that needs no link (tests).
    public init(_ check: @escaping @Sendable () -> Bool) {
        self.init(lock: CompanionSubmissionLock(), check)
    }

    /// True while the current task isn't cancelled, the link is open and its authorisation stands.
    public func isCurrent() -> Bool {
        !Task.isCancelled && lock.isOpen && check()
    }

    /// Runs `body` (the submission) only if the token is current, atomically with respect to
    /// the link closing. Nil when it isn't.
    public func perform<T: Sendable>(_ body: () -> T) -> T? {
        guard !Task.isCancelled else { return nil }
        return lock.perform(isAuthorized: check, body)
    }

    /// Starts `operation` as a task only if the token is current, atomically with respect to the
    /// link closing, and ties the task to the link: a close or revoke from then on cancels it
    /// (#586). Nil when the token isn't current. Model work for a phone starts here, and checks
    /// `isCurrent()` again right before the model is asked.
    public func start<Success: Sendable>(_ operation: @escaping @Sendable () async -> Success) -> Task<Success, Never>? {
        guard !Task.isCancelled else { return nil }
        let lock = lock
        return lock.start(isAuthorized: check) { id in
            Task {
                defer { lock.end(id) }
                return await operation()
            }
        }
    }

    /// Always authorised: for tests, and for callers that aren't serving a companion link.
    public static let always = CompanionAuthorization { true }
}
