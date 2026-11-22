import Foundation

/// Settings › Monitoring › Timing: the check interval and timeout a new target starts with
/// (#445). Existing targets keep their own.
enum TargetDefaults {
    static let intervalKey = "netmonitor.monitoring.defaultInterval"
    static let timeoutKey = "netmonitor.monitoring.defaultTimeout"
    static let defaultInterval = 30
    static let defaultTimeout = 5

    /// Seconds between checks.
    static func interval(in defaults: UserDefaults = .standard) -> Double {
        Double(defaults.object(forKey: intervalKey) as? Int ?? defaultInterval)
    }

    /// Seconds before a check fails.
    static func timeout(in defaults: UserDefaults = .standard) -> Double {
        Double(defaults.object(forKey: timeoutKey) as? Int ?? defaultTimeout)
    }
}
