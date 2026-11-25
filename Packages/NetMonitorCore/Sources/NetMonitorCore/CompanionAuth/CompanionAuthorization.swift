import Foundation

/// Whether the companion link a request came in on is still authorised (#590): bound to that
/// link's credential generation, so a revoke or a closed link turns it false. Work started for
/// a phone checks it, together with task cancellation, after every suspension and right before
/// anything with an effect, such as submitting to the model.
public struct CompanionAuthorization: Sendable {
    private let check: @Sendable () async -> Bool

    public init(_ check: @escaping @Sendable () async -> Bool) {
        self.check = check
    }

    /// True while the task isn't cancelled and the link's authorisation still stands.
    public func isCurrent() async -> Bool {
        guard !Task.isCancelled else { return false }
        let current = await check()
        return current && !Task.isCancelled
    }

    /// Always authorised: for tests, and for callers that aren't serving a companion link.
    public static let always = CompanionAuthorization { true }
}
