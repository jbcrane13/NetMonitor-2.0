import Foundation
import Synchronization

/// One companion link's submission lock (#590). Submitting work for the link (asking the model)
/// and closing the link both take it, so they never overlap: a close waits for a submission
/// already inside, and no submission starts after a close returns.
public final class CompanionSubmissionLock: Sendable {
    private let open = Mutex(true)

    public init() {}

    public var isOpen: Bool {
        open.withLock { $0 }
    }

    /// Closes the link for submissions, after any submission in progress has finished.
    public func close() {
        open.withLock { $0 = false }
    }

    /// Runs `body` only while the link is open and `isAuthorized` holds, with both checks and
    /// `body` inside one critical section that `close` can't interleave with.
    func perform<T: Sendable>(isAuthorized: () -> Bool, _ body: () -> T) -> T? {
        open.withLock { isOpen in
            guard isOpen, isAuthorized() else { return nil }
            return body()
        }
    }
}

/// Whether the companion link a request came in on is still authorised (#590): bound to that
/// link's submission lock and credential generation, so a revoke or a close turns it false.
///
/// Work for a phone checks `isCurrent()` after every suspension. The model is asked only through
/// `perform(_:)`, which checks and submits inside the link's lock; the Mac's Remove closes that
/// lock before it revokes the phone's key, so a revoke either comes before the submission (the
/// model is never asked) or after it (closing the link then cancels the task, which stops it).
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

    /// Always authorised: for tests, and for callers that aren't serving a companion link.
    public static let always = CompanionAuthorization { true }
}
