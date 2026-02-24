import Foundation

// MARK: - WorldPingCheckResult

/// Aggregated result from a complete world ping check (all locations).
public struct WorldPingCheckResult: Sendable {
    public let host: String
    public let requestId: String
    public let locationResults: [WorldPingLocationResult]
    public let completedAt: Date

    public init(host: String, requestId: String, locationResults: [WorldPingLocationResult], completedAt: Date = Date()) {
        self.host = host
        self.requestId = requestId
        self.locationResults = locationResults
        self.completedAt = completedAt
    }

    /// Average latency across successful nodes, in milliseconds.
    public var averageLatencyMs: Double? {
        let latencies = locationResults.compactMap { $0.latencyMs }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    /// Minimum (best) latency across successful nodes.
    public var minimumLatencyMs: Double? {
        locationResults.compactMap { $0.latencyMs }.min()
    }

    /// Maximum (worst) latency across successful nodes.
    public var maximumLatencyMs: Double? {
        locationResults.compactMap { $0.latencyMs }.max()
    }

    /// Number of nodes that responded successfully.
    public var successCount: Int {
        locationResults.filter { $0.isSuccess }.count
    }

    /// Success rate as a value 0.0–1.0.
    public var successRate: Double {
        guard !locationResults.isEmpty else { return 0 }
        return Double(successCount) / Double(locationResults.count)
    }
}
