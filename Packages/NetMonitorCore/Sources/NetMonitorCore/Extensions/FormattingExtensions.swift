import Foundation

/// Formats a speed value (in Mbps) into a human-readable string.
///
/// Conversion rules:
/// - Values <= 0: returns "0 Mbps"
/// - Values >= 1000: converts to Gbps with 2 decimal places (e.g. "1.25 Gbps")
/// - Values >= 100 Mbps: 0 decimal places (e.g. "250 Mbps")
/// - Values >= 10 Mbps: 1 decimal place (e.g. "45.3 Mbps")
/// - Values < 10 Mbps: 2 decimal places (e.g. "3.14 Mbps")
public func formatSpeed(_ mbps: Double) -> String {
    guard mbps > 0 else { return "0 Mbps" }
    if mbps >= 1000 {
        return String(format: "%.2f Gbps", mbps / 1000)
    } else if mbps >= 100 {
        return String(format: "%.0f Mbps", mbps)
    } else if mbps >= 10 {
        return String(format: "%.1f Mbps", mbps)
    } else {
        return String(format: "%.2f Mbps", mbps)
    }
}

/// Formats a duration in seconds as a human-readable time string.
///
/// - Parameters:
///   - seconds: The duration in seconds.
///   - alwaysShowHours: When `true`, always emits `HH:MM:SS` with leading zeros on
///     the hours component (e.g. `"01:02:03"`). When `false` (default), the hours
///     component is omitted when zero and has no leading zero when non-zero
///     (e.g. `"2:03"` or `"1:02:03"`). This is the VPN-connection-time convention.
///
/// Examples:
/// ```swift
/// formatDuration(75)                          // "1:15"
/// formatDuration(3723)                        // "1:02:03"
/// formatDuration(75,    alwaysShowHours: true) // "00:01:15"
/// formatDuration(3723,  alwaysShowHours: true) // "01:02:03"
/// ```
public func formatDuration(_ seconds: TimeInterval, alwaysShowHours: Bool = false) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if alwaysShowHours {
        return String(format: "%02d:%02d:%02d", h, m, s)
    } else if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%d:%02d", m, s)
    }
}
