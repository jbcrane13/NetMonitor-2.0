import Foundation
import Observation
import Synchronization

/// Whether the user lets this phone send model requests to their Mac (#457). Requests go to
/// the Mac over the local network, so the phone asks once, the first time a connected Mac could
/// answer something the local model can't. Until the user agrees, the Mac route counts as
/// unavailable and features fall back. A Settings switch changes the answer later.
///
/// `decision` is observable, so the prompt and the features redraw when it changes.
public final class MacInsightConsent: Sendable, Observable {
    /// Where the answer about explanations and summaries (`insight.v1`) is kept.
    public static let defaultsKey = "netmonitor.macInsight.consent"
    /// Where the answer about typed text (`rules.v1`, `symptoms.v1`) is kept (#586): asked
    /// once more, since what the user types is a new kind of data to send. A "yes" to
    /// explanations doesn't cover it.
    public static let readingDefaultsKey = "netmonitor.macInsight.consent.v2"

    // `UserDefaults` is documented as thread-safe; it isn't marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults?
    private let key: String
    private let stored: Mutex<State>
    private let registrar = ObservationRegistrar()

    private struct State {
        var decision: Bool?
        /// Goes up with every change of answer (#586), so work begun under an earlier "yes" can
        /// tell the answer changed even when it is "yes" again.
        var generation = 0
        var onWithdrawal: [UUID: @Sendable () -> Void] = [:]
    }

    /// Reads the answer under `key` from `defaults`; nil `defaults` keeps it in memory only,
    /// starting at `decision`.
    public init(defaults: UserDefaults?, decision: Bool? = nil, key: String = MacInsightConsent.defaultsKey) {
        self.defaults = defaults
        self.key = key
        stored = Mutex(State(decision: defaults?.object(forKey: key) as? Bool ?? decision))
    }

    /// True once the user agreed, false once they declined, nil before they are asked.
    public var decision: Bool? {
        registrar.access(self, keyPath: \.decision)
        return stored.withLock { $0.decision }
    }

    /// The current answer's generation while it is "yes"; nil otherwise. Work sent under one
    /// generation is valid only while it is still the current one.
    public var allowedGeneration: Int? {
        stored.withLock { $0.decision == true ? $0.generation : nil }
    }

    /// Calls `handler` the next times the user withdraws a "yes", until `removeWithdrawalHandler`.
    public func addWithdrawalHandler(_ handler: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        stored.withLock { $0.onWithdrawal[id] = handler }
        return id
    }

    public func removeWithdrawalHandler(_ id: UUID) {
        _ = stored.withLock { $0.onWithdrawal.removeValue(forKey: id) }
    }

    /// Whether requests may go to the Mac.
    public var isAllowed: Bool { decision == true }

    /// The user agreed in the prompt.
    public func agree() { setAllowed(true) }

    /// The user declined in the prompt: the route stays off until the Settings switch.
    public func decline() { setAllowed(false) }

    /// The Settings switch.
    public func setAllowed(_ allowed: Bool) {
        let withdrawn: [@Sendable () -> Void] = registrar.withMutation(of: self, keyPath: \.decision) {
            stored.withLock { state in
                guard state.decision != allowed else { return [] }
                let wasAllowed = state.decision == true
                state.decision = allowed
                state.generation += 1
                return wasAllowed ? Array(state.onWithdrawal.values) : []
            }
        }
        defaults?.set(allowed, forKey: key)
        withdrawn.forEach { $0() }
    }
}

/// Work under one "yes" (#586, #635): valid while that answer stands, even across a withdraw and
/// agree-again, after which it isn't.
public struct ConsentGeneration: Sendable {
    let consent: MacInsightConsent
    let generation: Int

    /// Whether the answer this began under still stands.
    public var isCurrent: @Sendable () -> Bool {
        { [consent, generation] in consent.allowedGeneration == generation }
    }

    /// Calls `handler` when the user withdraws this answer, or at once if they already did between
    /// the check and now. Returns what removes the handler.
    public func onWithdrawal(_ handler: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let id = consent.addWithdrawalHandler(handler)
        let consent = consent
        if !isCurrent() {
            handler()
        }
        return { consent.removeWithdrawalHandler(id) }
    }
}

extension MacInsightConsent {
    /// The current "yes", to run work under; nil when the user hasn't agreed.
    public var currentGeneration: ConsentGeneration? {
        allowedGeneration.map { ConsentGeneration(consent: self, generation: $0) }
    }
}
