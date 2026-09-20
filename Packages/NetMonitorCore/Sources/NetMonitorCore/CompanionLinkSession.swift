import Foundation

/// Tracks liveness and reconnect backoff state for a Mac–iOS companion link.
///
/// The caller supplies the clock via `now:`/`at:` parameters on every method — this type never
/// reads `Date()` internally — which keeps it a pure value type and its tests deterministic.
///
/// Liveness is recorded on *any* inbound companion message, not only heartbeats: any traffic
/// proves the link is alive, so gating on heartbeats alone would misclassify a busy link as dead.
///
/// This type does not own `connectionGeneration` (ADR-007's generation-ID guard against stale
/// callbacks) — that concern is orthogonal and remains on the owning service.
public struct CompanionLinkSession: Sendable {
    public let heartbeatInterval: TimeInterval
    public let missedBeatsBeforeStale: Int

    public private(set) var lastReceived: Date?
    public private(set) var reconnectAttempt: Int = 0

    public init(heartbeatInterval: TimeInterval = 15, missedBeatsBeforeStale: Int = 3) {
        self.heartbeatInterval = heartbeatInterval
        self.missedBeatsBeforeStale = missedBeatsBeforeStale
    }

    // MARK: - Liveness

    /// Records that a message was received from the companion at `instant`.
    public mutating func recordReceived(at instant: Date) {
        lastReceived = instant
    }

    /// Whether the link should still be considered alive as of `now`.
    ///
    /// Returns `false` if nothing has ever been received, or if the time since the last
    /// received message exceeds `heartbeatInterval * missedBeatsBeforeStale`.
    public func isAlive(now: Date) -> Bool {
        guard let lastReceived else { return false }
        let staleAfter = heartbeatInterval * Double(missedBeatsBeforeStale)
        return now.timeIntervalSince(lastReceived) < staleAfter
    }

    // MARK: - Reconnect

    /// Records a successful connection at `instant`, resetting the reconnect attempt counter
    /// and liveness tracking.
    public mutating func recordConnected(at instant: Date) {
        reconnectAttempt = 0
        lastReceived = instant
    }

    /// Increments the reconnect attempt counter and returns the delay to wait before the next
    /// attempt, using the same capped-exponential-backoff-with-jitter formula as the original
    /// `MacConnectionService.reconnectDelay(attempt:jitterFraction:)`.
    public mutating func nextReconnectDelay(jitterFraction: Double) -> TimeInterval {
        reconnectAttempt += 1
        return Self.reconnectDelay(attempt: reconnectAttempt, jitterFraction: jitterFraction)
    }

    /// Resets reconnect and liveness state to its initial values.
    public mutating func reset() {
        reconnectAttempt = 0
        lastReceived = nil
    }

    /// Capped exponential backoff with jitter: `min(60, 2^(attempt-1))` plus jitter of up to
    /// 25% of that base, itself capped at 60s total.
    public static func reconnectDelay(attempt: Int, jitterFraction: Double) -> TimeInterval {
        let exponent = Double(max(attempt - 1, 0))
        let base = min(60, pow(2, exponent))
        let jitter = base * 0.25 * min(max(jitterFraction, 0), 1)
        return min(60, base + jitter)
    }
}
