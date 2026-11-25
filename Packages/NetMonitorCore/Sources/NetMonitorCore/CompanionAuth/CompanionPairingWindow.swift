import Foundation
import Security

/// One pairing window on the Mac (#590): an immutable generation, two one-time secrets (the
/// QR's 256 bits and the typed 125-bit code), and a deadline on a monotonic clock (the caller
/// passes `ProcessInfo.systemUptime`).
///
/// It goes open → consumed exactly once, and both secrets burn together. The owner checks it and
/// consumes it synchronously, before any suspension.
public struct CompanionPairingWindow: Sendable {
    public static let lifetime: TimeInterval = 600
    /// Pairing connections one window admits. It caps attempts to grind the 6-digit comparison code.
    public static let maximumConnections = 8

    public enum State: Sendable, Equatable { case open, consumed, closed }

    public let generation: UUID
    public let code: CompanionPairingCode
    public let deadline: TimeInterval
    public private(set) var state: State = .open
    public private(set) var admittedConnections = 0
    private let qrSecret: Data

    /// `code` is random unless a test passes its own.
    public init(opening now: TimeInterval, code: CompanionPairingCode = .random()) {
        generation = UUID()
        self.code = code
        deadline = now + Self.lifetime
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        qrSecret = Data(bytes)
    }

    public func isOpen(now: TimeInterval) -> Bool {
        state == .open && now < deadline
    }

    /// Counts a new pairing connection; false once the window is shut or full.
    public mutating func admit(now: TimeInterval) -> Bool {
        guard isOpen(now: now), admittedConnections < Self.maximumConnections else { return false }
        admittedConnections += 1
        return true
    }

    /// Open → consumed, only for this window's own generation and before its deadline.
    public mutating func consume(generation: UUID, now: TimeInterval) -> Bool {
        guard generation == self.generation, isOpen(now: now) else { return false }
        state = .consumed
        return true
    }

    public mutating func close() {
        if state == .open {
            state = .closed
        }
    }

    public func secret(for kind: CompanionPairingProof.Kind) -> Data {
        switch kind {
        case .qr: qrSecret
        case .code: code.secret
        }
    }
}
