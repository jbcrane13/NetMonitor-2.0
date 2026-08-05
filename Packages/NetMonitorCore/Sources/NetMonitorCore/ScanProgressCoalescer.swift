import Foundation

/// Deterministic gate for coalescing high-frequency scan progress updates.
/// Phase transitions and completion are always published.
public struct ScanProgressCoalescer: Sendable {
    private let minimumInterval: TimeInterval
    private var lastPublishedAt: TimeInterval?
    private var lastPhase: String?

    public init(minimumInterval: TimeInterval = 0.1) {
        self.minimumInterval = minimumInterval
    }

    public mutating func shouldPublish(
        progress: Double,
        phase: String,
        timestamp: TimeInterval
    ) -> Bool {
        let phaseChanged = phase != lastPhase
        let intervalElapsed = lastPublishedAt.map { timestamp - $0 >= minimumInterval } ?? true
        guard phaseChanged || progress >= 1 || intervalElapsed else { return false }

        lastPhase = phase
        lastPublishedAt = timestamp
        return true
    }
}
