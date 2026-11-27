import Foundation
import Synchronization

/// Who may use the on-device model now, in this process (#586). Every caller registers here:
///
/// - **interactive** local work (a rule or symptom typed on this device, an explanation, Ask)
///   never waits, and while any runs, companion work is refused `busy`;
/// - **background** local work (identity suggestions) never waits and never holds the companion
///   back: it is the lowest priority;
/// - **companion** work (a paired phone's request) gets the one companion slot, only while no
///   interactive work runs and within a rolling budget (`companionBudget` per `budgetWindow`),
///   so a phone can't keep the Mac's model busy by refilling its per-link allowance.
///
/// The companion slot is held by a ``Ticket`` until the model call it covers has really
/// returned, and only that ticket releases it: a cancelled or timed-out request whose model
/// ignores cancellation keeps the slot until it stops.
public final class ModelAdmission: Sendable {
    public static let shared = ModelAdmission()

    public enum Priority: Sendable {
        case interactive
        case background
    }

    /// The companion slot, held by one request.
    public struct Ticket: Sendable, Hashable {
        let id: UUID
    }

    /// Companion requests admitted per `budgetWindow`.
    public static let defaultCompanionBudget = 10
    public static let defaultBudgetWindow: Duration = .seconds(60)

    private struct State {
        var interactive = 0
        var companion: Ticket?
        var admitted: [ContinuousClock.Instant] = []
    }

    private let state = Mutex(State())
    private let companionBudget: Int
    private let budgetWindow: Duration
    private let now: @Sendable () -> ContinuousClock.Instant

    public init(
        companionBudget: Int = defaultCompanionBudget,
        budgetWindow: Duration = defaultBudgetWindow,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.companionBudget = companionBudget
        self.budgetWindow = budgetWindow
        self.now = now
    }

    /// Runs local model work at `priority`. It never waits.
    public func runLocal<T: Sendable>(_ priority: Priority, _ body: () async throws -> T) async rethrows -> T {
        guard priority == .interactive else { return try await body() }
        state.withLock { $0.interactive += 1 }
        defer { state.withLock { $0.interactive -= 1 } }
        return try await body()
    }

    /// The companion slot, or nil (answer `busy`) while interactive work runs, another companion
    /// request holds the slot, or the budget is spent.
    public func admitCompanion() -> Ticket? {
        let instant = now()
        let window = budgetWindow
        let budget = companionBudget
        return state.withLock { state in
            state.admitted.removeAll { instant - $0 >= window }
            guard state.interactive == 0, state.companion == nil, state.admitted.count < budget else { return nil }
            let ticket = Ticket(id: UUID())
            state.companion = ticket
            state.admitted.append(instant)
            return ticket
        }
    }

    /// Frees the slot, only for the ticket that holds it.
    public func release(_ ticket: Ticket) {
        state.withLock { state in
            if state.companion == ticket {
                state.companion = nil
            }
        }
    }

    /// Whether a companion request holds the slot.
    public var isCompanionSlotHeld: Bool { state.withLock { $0.companion != nil } }
}

/// The gate right in front of a model call (#586). The model adapter starts the model only
/// inside ``run(_:)``, which checks with no suspension before the call that the task isn't
/// cancelled and that `mayStart` still holds: for a companion request, that the link is still
/// authorised (`CompanionAuthorization.isCurrent()`) and the Mac still answers iPhone requests.
///
/// A revoke that lands after the check closes the link first, which cancels the work, so the
/// model call is cancelled: the same guarantee `CompanionAuthorization.perform` gives a
/// synchronous submission.
public struct ModelSubmission: Sendable {
    private let mayStart: @Sendable () -> Bool
    private let beforeStart: (@Sendable () async -> Void)?

    /// - Parameter beforeStart: tests only: runs right before the check, so a test can revoke
    ///   the link between the work starting and the model being asked.
    public init(mayStart: @escaping @Sendable () -> Bool, beforeStart: (@Sendable () async -> Void)? = nil) {
        self.mayStart = mayStart
        self.beforeStart = beforeStart
    }

    /// For this device's own requests: nothing to check beyond cancellation.
    public static let local = ModelSubmission(mayStart: { true })

    public struct Refused: Error {}

    /// Runs `body` (the model call) if the task isn't cancelled and `mayStart` holds; throws
    /// ``Refused`` otherwise.
    public func run<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        await beforeStart?()
        guard !Task.isCancelled, mayStart() else { throw Refused() }
        return try await body()
    }
}
