import Foundation

/// One saved network health score, for the health-over-time chart (#491 D10).
public struct HealthScoreSample: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// The `NetworkProfile.id` the score was measured on.
    public let networkProfileID: UUID
    public let timestamp: Date
    /// 0–100.
    public let score: Int
    /// A/B/C/D/F.
    public let grade: String

    public init(id: UUID = UUID(), networkProfileID: UUID, timestamp: Date, score: Int, grade: String) {
        self.id = id
        self.networkProfileID = networkProfileID
        self.timestamp = timestamp
        self.score = score
        self.grade = grade
    }
}

public extension HealthScoreSample {
    /// The score range a history chart plots: the samples' range with 10 points either side,
    /// within 0–100, so a small change still shows as a slope.
    static func chartDomain(_ samples: [HealthScoreSample]) -> ClosedRange<Int> {
        guard let low = samples.map(\.score).min(), let high = samples.map(\.score).max() else { return 0...100 }
        return max(0, low - 10)...min(100, high + 10)
    }
}
