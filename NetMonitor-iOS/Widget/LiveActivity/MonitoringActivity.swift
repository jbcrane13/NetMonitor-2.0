import Foundation
#if os(iOS)
import ActivityKit

/// ActivityAttributes for ongoing network monitoring.
/// Static data: when monitoring started.
/// ContentState: live connection status, latency, and alerts.
struct MonitoringActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Whether the device is currently connected.
        var isConnected: Bool
        /// Current gateway latency in milliseconds, if available.
        var latencyMs: Double?
        /// Number of active alerts (e.g. devices appearing/disappearing).
        var alertCount: Int
        /// Short status string (e.g. "Connected · Wi-Fi", "Offline").
        var statusMessage: String
        /// Display name of the connection type (e.g. "Wi-Fi", "Cellular").
        var connectionType: String
    }

    /// When this monitoring session started.
    var startTime: Date
    /// Display name of the monitored network, if known.
    var networkName: String?
}
#endif
