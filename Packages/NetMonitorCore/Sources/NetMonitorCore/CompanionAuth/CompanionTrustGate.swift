import Foundation

/// The Mac's live trust state for the companion link (#590): which phone pins are trusted (each
/// with a credential generation) and the pairing window.
///
/// It is lock-guarded and synchronous because the TLS verify block reads it on Network.framework's
/// queue. Every check and change happens under one lock, so a revoke is in force the moment
/// `revoke` returns: before any socket is cancelled or Keychain item deleted.
public final class CompanionTrustGate: @unchecked Sendable {
    private let lock = NSLock()
    private let now: @Sendable () -> TimeInterval
    private var trusted: [Data: UInt64] = [:]
    private var nextGeneration: UInt64 = 1
    private var window: CompanionPairingWindow?
    /// The link that consumed the window and may finish pairing.
    private var consumer: UUID?

    /// `now` is a monotonic clock in seconds; it defaults to system uptime.
    public init(paired pins: [Data], now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        for pin in pins { trustLocked(pin) }
    }

    // MARK: - Handshake and binding

    /// For the verify block: a trusted pin, or any other pin while a window can still admit.
    public func acceptsAtHandshake(_ pin: Data) -> Bool {
        locked {
            if trusted[pin] != nil {
                return true
            }
            guard let window, window.isOpen(now: now()) else { return false }
            return window.admittedConnections < CompanionPairingWindow.maximumConnections
        }
    }

    /// The role of a verified session's peer, or nil to close it. A pairing role uses one of
    /// the window's admissions.
    public func classify(_ pin: Data) -> CompanionLinkRole? {
        locked {
            if let generation = trusted[pin] {
                return .paired(pin: pin, generation: generation)
            }
            guard var window, window.admit(now: now()) else { return nil }
            self.window = window
            return .pairing(window: window.generation)
        }
    }

    /// Whether `role` still stands: a paired pin not revoked since it bound, or a pairing window
    /// still open (or consumed by this very link).
    public func isAuthorized(_ role: CompanionLinkRole, link: UUID) -> Bool {
        locked {
            switch role {
            case .paired(let pin, let generation):
                return trusted[pin] == generation
            case .pairing(let generation):
                guard let window, window.generation == generation, now() < window.deadline else { return false }
                switch window.state {
                case .open: return true
                case .consumed: return consumer == link
                case .closed: return false
                }
            }
        }
    }

    // MARK: - Trust

    public func trust(_ pin: Data) {
        locked { trustLocked(pin) }
    }

    /// Denies `pin` at once, in memory, whatever happens to its Keychain item afterwards.
    public func revoke(_ pin: Data) {
        locked { trusted[pin] = nil }
    }

    // MARK: - Pairing window

    /// Opens a new window, shutting any earlier one.
    @discardableResult
    public func openWindow() -> CompanionPairingWindow {
        locked {
            let opened = CompanionPairingWindow(opening: now())
            window = opened
            consumer = nil
            return opened
        }
    }

    public func closeWindow() {
        locked {
            window?.close()
        }
    }

    /// The pairing step: verify the phone's proof, then consume the window, in one critical
    /// section with no suspension. Nil when the role, window, proof or pin doesn't hold; a wrong
    /// proof doesn't burn the window.
    public func beginPairing(
        link: UUID,
        role: CompanionLinkRole,
        request: PairRequestPayload,
        session: CompanionVerifiedSession,
        macPin: Data
    ) -> CompanionPairingStep? {
        locked {
            guard case .pairing(let generation) = role,
                  var window, window.generation == generation, window.isOpen(now: now()),
                  trusted[session.peerPin] == nil,
                  CompanionPairingProof.verify(
                      request.proof, role: .phone, kind: request.kind, secret: window.secret(for: request.kind),
                      binding: .init(exporter: session.exporter, macPin: macPin, phonePin: session.peerPin)
                  ),
                  window.consume(generation: generation, now: now()) else { return nil }
            self.window = window
            consumer = link
            return CompanionPairingStep(
                window: generation,
                phonePin: session.peerPin,
                challenge: CompanionPairingProof.make(
                    role: .mac, kind: request.kind, secret: window.secret(for: request.kind),
                    binding: .init(exporter: session.exporter, macPin: macPin, phonePin: session.peerPin)
                ),
                comparisonCode: CompanionPairingProof.comparisonCode(
                    exporter: session.exporter, macPin: macPin, phonePin: session.peerPin
                )
            )
        }
    }

    // MARK: - Private

    private func trustLocked(_ pin: Data) {
        trusted[pin] = nextGeneration
        nextGeneration += 1
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// What the Mac sends and shows once a phone's pairing proof checks out.
public struct CompanionPairingStep: Sendable, Equatable {
    public let window: UUID
    public let phonePin: Data
    /// The Mac's proof of the same secret, for `pairChallenge`.
    public let challenge: Data
    /// What both screens show; the user confirms on the Mac that they match.
    public let comparisonCode: String
}
