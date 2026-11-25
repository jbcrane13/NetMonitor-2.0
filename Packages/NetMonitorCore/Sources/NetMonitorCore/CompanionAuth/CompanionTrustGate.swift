import Foundation
import Synchronization

/// The Mac's live trust state for the companion link (#590): which phone pins are trusted (each
/// with a credential generation) and the pairing window.
///
/// Synchronous and guarded by one `Mutex`, so a revoke is in force the moment `revoke` returns:
/// before any socket is cancelled or Keychain item deleted.
public final class CompanionTrustGate: Sendable {
    private struct State {
        var trusted: [Data: UInt64] = [:]
        var nextGeneration: UInt64 = 1
        var window: CompanionPairingWindow?
        /// The link that consumed the window and may finish pairing.
        var consumer: UUID?

        mutating func trust(_ pin: Data) {
            trusted[pin] = nextGeneration
            nextGeneration += 1
        }
    }

    private let state: Mutex<State>
    private let now: @Sendable () -> TimeInterval

    /// `now` is a monotonic clock in seconds; it defaults to system uptime.
    public init(paired pins: [Data], now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        var initial = State()
        for pin in pins {
            initial.trust(pin)
        }
        state = Mutex(initial)
    }

    // MARK: - Binding

    /// The role of a verified session's peer, or nil to refuse it. A pairing role uses one of
    /// the window's admissions.
    public func classify(_ pin: Data) -> CompanionLinkRole? {
        let now = now()
        return state.withLock { state in
            if let generation = state.trusted[pin] {
                return .paired(pin: pin, generation: generation)
            }
            guard var window = state.window, window.admit(now: now) else { return nil }
            state.window = window
            return .pairing(window: window.generation)
        }
    }

    /// Whether `role` still stands: a paired pin not revoked since it bound, or a pairing window
    /// still open (or consumed by this very link).
    public func isAuthorized(_ role: CompanionLinkRole, link: UUID) -> Bool {
        let now = now()
        return state.withLock { state in
            switch role {
            case .paired(let pin, let generation):
                return state.trusted[pin] == generation
            case .pairing(let generation):
                guard let window = state.window, window.generation == generation, now < window.deadline else { return false }
                switch window.state {
                case .open: return true
                case .consumed: return state.consumer == link
                case .closed: return false
                }
            }
        }
    }

    // MARK: - Trust

    public func trust(_ pin: Data) {
        state.withLock { $0.trust(pin) }
    }

    /// Denies `pin` at once, in memory, whatever happens to its Keychain item afterwards.
    public func revoke(_ pin: Data) {
        _ = state.withLock { $0.trusted.removeValue(forKey: pin) }
    }

    // MARK: - Pairing window

    /// Opens a new window, shutting any earlier one. `code` is random unless a test passes one.
    @discardableResult
    public func openWindow(code: CompanionPairingCode = .random()) -> CompanionPairingWindow {
        let opened = CompanionPairingWindow(opening: now(), code: code)
        state.withLock { state in
            state.window = opened
            state.consumer = nil
        }
        return opened
    }

    public func closeWindow() {
        state.withLock { $0.window?.close() }
    }

    /// The pairing step: verify the phone's proof, then consume the window, in one critical
    /// section with no suspension. Nil when the role, window, proof, nonce or pin doesn't hold; a
    /// wrong proof doesn't burn the window.
    public func beginPairing(
        link: UUID,
        role: CompanionLinkRole,
        request: PairRequestPayload,
        session: CompanionVerifiedSession,
        macPin: Data,
        macNonce: Data
    ) -> CompanionPairingStep? {
        let now = now()
        let binding = CompanionPairingProof.Binding(exporter: session.exporter, macPin: macPin, phonePin: session.peerPin)
        return state.withLock { state -> CompanionPairingStep? in
            guard case .pairing(let generation) = role,
                  var window = state.window, window.generation == generation, window.isOpen(now: now),
                  state.trusted[session.peerPin] == nil,
                  request.nonce.count == 32, macNonce.count == 32,
                  CompanionPairingProof.verify(
                      request.proof, role: .phone, kind: request.kind, secret: window.secret(for: request.kind), binding: binding
                  ),
                  window.consume(generation: generation, now: now) else { return nil }
            state.window = window
            state.consumer = link
            return CompanionPairingStep(
                window: generation,
                phonePin: session.peerPin,
                challenge: CompanionPairingProof.make(
                    role: .mac, kind: request.kind, secret: window.secret(for: request.kind), binding: binding
                ),
                macNonce: macNonce,
                comparisonCode: CompanionPairingProof.comparisonCode(
                    exporter: session.exporter, macPin: macPin, phonePin: session.peerPin,
                    macNonce: macNonce, phoneNonce: request.nonce
                )
            )
        }
    }
}

/// What the Mac sends and shows once a phone's pairing proof checks out.
public struct CompanionPairingStep: Sendable, Equatable {
    public let window: UUID
    public let phonePin: Data
    /// The Mac's proof of the same secret, for `pairChallenge`.
    public let challenge: Data
    /// The nonce the Mac committed to in `serverHello`, revealed in `pairChallenge`.
    public let macNonce: Data
    /// What both screens show; the user confirms on the Mac that they match.
    public let comparisonCode: String
}
