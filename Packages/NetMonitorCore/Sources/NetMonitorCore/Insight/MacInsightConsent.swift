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
    /// Where the answer is kept.
    public static let defaultsKey = "netmonitor.macInsight.consent"

    // `UserDefaults` is documented as thread-safe; it isn't marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults?
    private let stored: Mutex<Bool?>
    private let registrar = ObservationRegistrar()

    /// Reads the answer from `defaults`; nil `defaults` keeps it in memory only, starting at
    /// `decision`.
    public init(defaults: UserDefaults?, decision: Bool? = nil) {
        self.defaults = defaults
        stored = Mutex(defaults?.object(forKey: Self.defaultsKey) as? Bool ?? decision)
    }

    /// True once the user agreed, false once they declined, nil before they are asked.
    public var decision: Bool? {
        registrar.access(self, keyPath: \.decision)
        return stored.withLock { $0 }
    }

    /// Whether requests may go to the Mac.
    public var isAllowed: Bool { decision == true }

    /// The user agreed in the prompt.
    public func agree() { setAllowed(true) }

    /// The user declined in the prompt: the route stays off until the Settings switch.
    public func decline() { setAllowed(false) }

    /// The Settings switch.
    public func setAllowed(_ allowed: Bool) {
        registrar.withMutation(of: self, keyPath: \.decision) {
            stored.withLock { $0 = allowed }
        }
        defaults?.set(allowed, forKey: Self.defaultsKey)
    }
}
