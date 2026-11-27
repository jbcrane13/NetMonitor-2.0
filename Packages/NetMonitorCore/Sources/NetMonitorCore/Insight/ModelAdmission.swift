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
/// The companion slot is held by a ``Ticket`` until the request and every model call made for it
/// (under ``withTicket(_:_:)``) have really returned, and only that ticket releases it: a
/// cancelled or timed-out request whose model ignores cancellation keeps the slot until it stops.
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
        /// Who still holds the companion ticket: the request, and every model call made for it.
        var companionHolds = 0
        var admitted: [ContinuousClock.Instant] = []
    }

    /// The companion ticket the current task works under, if any. Tasks inherit it, so a model
    /// call made for a companion request (even one in a task of its own, like
    /// `SystemInsightService.explain`'s) holds the ticket until it really returns.
    private struct Hold: Sendable {
        let admission: ModelAdmission
        let ticket: Ticket
    }

    @TaskLocal private static var hold: Hold?

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

    /// Runs a model call at `priority`; every model call in the process goes through here. It
    /// never waits. Made for a companion request (under ``withTicket(_:_:)``), it holds that
    /// request's ticket until it returns instead.
    public func runLocal<T: Sendable>(_ priority: Priority, _ body: () async throws -> T) async rethrows -> T {
        if let hold = Self.hold, hold.admission.retain(hold.ticket) {
            defer { hold.admission.release(hold.ticket) }
            return try await body()
        }
        guard priority == .interactive else { return try await body() }
        state.withLock { $0.interactive += 1 }
        defer { state.withLock { $0.interactive -= 1 } }
        return try await body()
    }

    /// Runs `body` as companion work under `ticket`: tasks it starts inherit the ticket, and
    /// their model calls hold it.
    public func withTicket<T>(_ ticket: Ticket, _ body: () throws -> T) rethrows -> T {
        try Self.$hold.withValue(Hold(admission: self, ticket: ticket), operation: body)
    }

    /// As ``withTicket(_:_:)``, for async work.
    public func withTicket<T: Sendable>(_ ticket: Ticket, _ body: () async throws -> T) async rethrows -> T {
        try await Self.$hold.withValue(Hold(admission: self, ticket: ticket), operation: body)
    }

    private func retain(_ ticket: Ticket) -> Bool {
        state.withLock { state in
            guard state.companion == ticket else { return false }
            state.companionHolds += 1
            return true
        }
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
            state.companionHolds = 1
            state.admitted.append(instant)
            return ticket
        }
    }

    /// Lets go of `ticket`. The slot is free once the request and every model call made for it
    /// have let go; another ticket's release never frees it.
    public func release(_ ticket: Ticket) {
        state.withLock { state in
            guard state.companion == ticket else { return }
            state.companionHolds -= 1
            if state.companionHolds <= 0 {
                state.companion = nil
                state.companionHolds = 0
            }
        }
    }

    /// Whether a companion request holds the slot.
    public var isCompanionSlotHeld: Bool { state.withLock { $0.companion != nil } }
}

/// The gate right in front of a model call (#586). The model adapter starts the model only
/// inside ``run(_:)``, which checks with no suspension before the call that the task isn't
/// cancelled, the link is still authorised and the Mac still answers iPhone requests.
///
/// The work it runs in was started with `CompanionAuthorization.start`, which registered it with
/// the link: a close or revoke after this check cancels the work, and with it the model call.
public struct ModelSubmission: Sendable {
    private let authorization: CompanionAuthorization
    private let isAllowed: @Sendable () -> Bool
    private let beforeCall: (@Sendable () async -> Void)?

    public init(authorization: CompanionAuthorization, isAllowed: @escaping @Sendable () -> Bool) {
        self.init(authorization: authorization, isAllowed: isAllowed, beforeCall: nil)
    }

    /// - Parameter beforeCall: tests only: runs after the work was registered with the link and
    ///   before the last check, so a test can close or revoke the link right there.
    init(authorization: CompanionAuthorization, isAllowed: @escaping @Sendable () -> Bool, beforeCall: (@Sendable () async -> Void)?) {
        self.authorization = authorization
        self.isAllowed = isAllowed
        self.beforeCall = beforeCall
    }

    /// For this device's own requests: nothing to check beyond cancellation.
    public static let local = ModelSubmission(authorization: .always, isAllowed: { true })

    public struct Refused: Error {}

    /// Runs `body` (the model call) if the task isn't cancelled, the link is authorised and the
    /// Mac answers; throws ``Refused`` otherwise.
    public func run<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        await beforeCall?()
        guard authorization.isCurrent(), isAllowed() else { throw Refused() }
        return try await body()
    }
}
