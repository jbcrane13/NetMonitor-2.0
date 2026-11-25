import Foundation

/// Whether the companion link a request came in on is still authorised (#590): bound to that
/// link's credential generation and to the link being open, so a revoke or a close turns it
/// false at once.
///
/// The check is synchronous on purpose. `InsightSummarizer` evaluates it in the same step that
/// submits to the model, with no suspension between, so a revoke either lands before the check
/// (the model is never asked) or after submission (the link's task is then cancelled, which
/// stops the stream). Work for a phone also checks it after every suspension.
public struct CompanionAuthorization: Sendable {
    private let check: @Sendable () -> Bool

    public init(_ check: @escaping @Sendable () -> Bool) {
        self.check = check
    }

    /// True while the current task isn't cancelled and the link's authorisation still stands.
    public func isCurrent() -> Bool {
        !Task.isCancelled && check()
    }

    /// Always authorised: for tests, and for callers that aren't serving a companion link.
    public static let always = CompanionAuthorization { true }
}
