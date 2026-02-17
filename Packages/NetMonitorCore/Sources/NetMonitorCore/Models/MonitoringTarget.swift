import Foundation
import SwiftData

/// iOS-derived monitoring target: tracks uptime and latency for a host.
/// Persisted via SwiftData.
@Model
public final class MonitoringTarget {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var host: String
    public var port: Int?
    public var targetProtocol: TargetProtocol
    public var isEnabled: Bool
    public var checkInterval: TimeInterval
    public var timeout: TimeInterval
    public var currentLatency: Double?
    public var averageLatency: Double?
    public var minLatency: Double?
    public var maxLatency: Double?
    public var isOnline: Bool
    public var consecutiveFailures: Int
    public var totalChecks: Int
    public var successfulChecks: Int
    public var lastChecked: Date?
    public var lastStatusChange: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int? = nil,
        targetProtocol: TargetProtocol = .icmp,
        isEnabled: Bool = true,
        checkInterval: TimeInterval = 60,
        timeout: TimeInterval = 5
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.targetProtocol = targetProtocol
        self.isEnabled = isEnabled
        self.checkInterval = checkInterval
        self.timeout = timeout
        self.isOnline = false
        self.consecutiveFailures = 0
        self.totalChecks = 0
        self.successfulChecks = 0
        self.createdAt = Date()
    }

    public var statusType: StatusType {
        isOnline ? .online : .offline
    }

    public var uptimePercentage: Double {
        guard totalChecks > 0 else { return 0 }
        return Double(successfulChecks) / Double(totalChecks) * 100
    }

    public var uptimeText: String {
        String(format: "%.1f%%", uptimePercentage)
    }

    public var latencyText: String? {
        guard let latency = currentLatency else { return nil }
        if latency < 1 { return "<1 ms" }
        return String(format: "%.0f ms", latency)
    }

    public var hostWithPort: String {
        if let port { return "\(host):\(port)" }
        return host
    }

    public func recordSuccess(latency: Double) {
        let wasOffline = !isOnline
        totalChecks += 1
        successfulChecks += 1
        consecutiveFailures = 0
        currentLatency = latency
        isOnline = true
        lastChecked = Date()
        if wasOffline { lastStatusChange = Date() }
        updateLatencyStats(latency)
    }

    public func recordFailure() {
        let wasOnline = isOnline
        totalChecks += 1
        consecutiveFailures += 1
        currentLatency = nil
        lastChecked = Date()
        if consecutiveFailures >= 3 {
            isOnline = false
            if wasOnline { lastStatusChange = Date() }
        }
    }

    private func updateLatencyStats(_ latency: Double) {
        if let current = averageLatency {
            let weight = min(Double(successfulChecks), 100.0)
            averageLatency = (current * (weight - 1) + latency) / weight
        } else {
            averageLatency = latency
        }
        if let min = minLatency {
            minLatency = Swift.min(min, latency)
        } else {
            minLatency = latency
        }
        if let max = maxLatency {
            maxLatency = Swift.max(max, latency)
        } else {
            maxLatency = latency
        }
    }
}
