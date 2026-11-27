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

    public enum Priority: Sendable, Hashable {
        case interactive
        case background
    }

    /// A companion slot, held by one request: the interactive slot or the background one.
    public struct Ticket: Sendable, Hashable {
        let id: UUID
        let priority: Priority
    }

    /// Companion requests admitted per `budgetWindow`.
    public static let defaultCompanionBudget = 10
    /// Background companion requests (a phone's identity suggestions, `identity.v1`) admitted per
    /// `budgetWindow`: a budget of their own, smaller, so a phone's background pass can't use up
    /// what typed requests need, nor typed requests starve it (#586).
    public static let defaultBackgroundBudget = 6
    public static let defaultBudgetWindow: Duration = .seconds(60)

    /// One companion slot: its ticket, who still holds it (the request and every model call made
    /// for it), and its rolling budget.
    private struct Slot {
        var ticket: Ticket?
        var holds = 0
        var admittedAt: ContinuousClock.Instant?
        var admitted: [ContinuousClock.Instant] = []
    }

    private struct State {
        var interactive = 0
        /// Two companion slots (#642 review): typed requests and insight in one, a phone's
        /// background identity in the other, so background work never holds interactive work back.
        /// At most two companion inferences at once.
        var slots: [Priority: Slot] = [.interactive: Slot(), .background: Slot()]
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
    private let backgroundBudget: Int
    private let budgetWindow: Duration
    private let now: @Sendable () -> ContinuousClock.Instant

    public init(
        companionBudget: Int = defaultCompanionBudget,
        backgroundBudget: Int = defaultBackgroundBudget,
        budgetWindow: Duration = defaultBudgetWindow,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.companionBudget = companionBudget
        self.backgroundBudget = backgroundBudget
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

    /// Starts `body` (a model call) as a task of its own that counts from this call, before the
    /// task first runs: under a companion ticket it holds the ticket at once, so the request
    /// letting go right after can't free the slot first; otherwise it registers at `priority`.
    public func task(_ priority: Priority, _ body: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        if let hold = Self.hold, hold.admission.retain(hold.ticket) {
            return Task {
                defer { hold.admission.release(hold.ticket) }
                await body()
            }
        }
        guard priority == .interactive else { return Task { await body() } }
        state.withLock { $0.interactive += 1 }
        return Task {
            defer { self.state.withLock { $0.interactive -= 1 } }
            await body()
        }
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
            guard state.slots[ticket.priority]?.ticket == ticket else { return false }
            state.slots[ticket.priority]?.holds += 1
            return true
        }
    }

    /// The slot for `priority`, or nil (answer `busy`) while the Mac's own interactive work runs,
    /// another companion request holds that slot, or that slot's budget is spent. `.interactive`
    /// is for typed requests and insight, `.background` for a phone's identity suggestions; each
    /// slot has its own budget, and neither waits for the other.
    public func admitCompanion(_ priority: Priority = .interactive) -> Ticket? {
        let instant = now()
        let window = budgetWindow
        let budget = priority == .interactive ? companionBudget : backgroundBudget
        return state.withLock { state in
            guard var slot = state.slots[priority] else { return nil }
            slot.admitted.removeAll { instant - $0 >= window }
            defer { state.slots[priority] = slot }
            guard state.interactive == 0, slot.ticket == nil, slot.admitted.count < budget else { return nil }
            let ticket = Ticket(id: UUID(), priority: priority)
            slot.ticket = ticket
            slot.holds = 1
            slot.admittedAt = instant
            slot.admitted.append(instant)
            return ticket
        }
    }

    /// Gives back what `ticket` spent of its budget: its request was cancelled before the model
    /// was asked (#642 review). Its slot stays held until it is released.
    public func refund(_ ticket: Ticket) {
        state.withLock { state in
            guard var slot = state.slots[ticket.priority], slot.ticket == ticket, let at = slot.admittedAt,
                  let index = slot.admitted.firstIndex(of: at) else { return }
            slot.admitted.remove(at: index)
            slot.admittedAt = nil
            state.slots[ticket.priority] = slot
        }
    }

    /// Lets go of `ticket`. Its slot is free once the request and every model call made for it
    /// have let go; another ticket's release never frees it.
    public func release(_ ticket: Ticket) {
        state.withLock { state in
            guard var slot = state.slots[ticket.priority], slot.ticket == ticket else { return }
            slot.holds -= 1
            if slot.holds <= 0 {
                slot.ticket = nil
                slot.holds = 0
                slot.admittedAt = nil
            }
            state.slots[ticket.priority] = slot
        }
    }

    /// Whether a companion request holds the interactive slot.
    public var isCompanionSlotHeld: Bool { state.withLock { $0.slots[.interactive]?.ticket != nil } }

    /// Whether a phone's background request holds the background slot.
    public var isBackgroundSlotHeld: Bool { state.withLock { $0.slots[.background]?.ticket != nil } }
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
    private let didStart: (@Sendable () -> Void)?

    public init(authorization: CompanionAuthorization, isAllowed: @escaping @Sendable () -> Bool) {
        self.init(authorization: authorization, isAllowed: isAllowed, beforeCall: nil)
    }

    /// - Parameters:
    ///   - beforeCall: tests only: runs after the work was registered with the link and before the
    ///     last check, so a test can close or revoke the link right there.
    ///   - didStart: runs when the model call starts, after the last check passed.
    init(
        authorization: CompanionAuthorization, isAllowed: @escaping @Sendable () -> Bool,
        beforeCall: (@Sendable () async -> Void)?, didStart: (@Sendable () -> Void)? = nil
    ) {
        self.authorization = authorization
        self.isAllowed = isAllowed
        self.beforeCall = beforeCall
        self.didStart = didStart
    }

    /// For this device's own requests: nothing to check beyond cancellation.
    public static let local = ModelSubmission(authorization: .always, isAllowed: { true })

    public struct Refused: Error {}

    /// Runs `body` (the model call) if the task isn't cancelled, the link is authorised and the
    /// Mac answers; throws ``Refused`` otherwise.
    public func run<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        await beforeCall?()
        guard authorization.isCurrent(), isAllowed() else { throw Refused() }
        didStart?()
        return try await body()
    }
}
