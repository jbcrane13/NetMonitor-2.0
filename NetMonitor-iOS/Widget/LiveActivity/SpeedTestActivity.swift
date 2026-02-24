import Foundation
#if os(iOS)
import ActivityKit

/// ActivityAttributes for an ongoing speed test.
/// Static data: none (a speed test has no meaningful static context).
/// ContentState: live speeds and current phase.
struct SpeedTestActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Current download speed in Mbps (0 until measured).
        var downloadSpeed: Double
        /// Current upload speed in Mbps (0 until measured).
        var uploadSpeed: Double
        /// Latency in milliseconds (0 until measured).
        var latency: Double
        /// Human-readable current phase (e.g. "Measuring latency…", "Testing download…").
        var phase: String
        /// Overall test progress from 0.0 to 1.0.
        var progress: Double
    }
}
#endif
