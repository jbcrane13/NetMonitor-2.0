import Foundation

/// Severity buckets for network health metrics, shared by every platform's UI.
extension NetworkHealthScore {
    public enum Severity: Sendable {
        case good
        case fair
        case poor
    }

    /// Buckets a latency reading: good < 50ms, fair < 150ms, otherwise poor.
    public static func latencySeverity(ms: Double) -> Severity {
        if ms < 50 {
            return .good
        }
        if ms < 150 {
            return .fair
        }
        return .poor
    }

    /// Buckets a WiFi signal strength percentage: good > 70%, fair > 40%, otherwise poor.
    public static func signalSeverity(percent: Int) -> Severity {
        if percent > 70 {
            return .good
        }
        if percent > 40 {
            return .fair
        }
        return .poor
    }
}
