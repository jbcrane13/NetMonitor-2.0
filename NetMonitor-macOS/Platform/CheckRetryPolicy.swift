import Foundation

/// How many consecutive failed checks mark a target down, from the "Retry failed checks"
/// setting in Monitoring settings (#392).
///
/// With retry off, one failed check marks the target down. With retry on, a target is
/// marked down only after `retryCount` consecutive failed checks.
struct CheckRetryPolicy: Equatable {
    static let enabledKey = "netmonitor.monitoring.retryEnabled"
    static let countKey = "netmonitor.monitoring.retryCount"
    static let defaultCount = 3

    let requiredFailures: Int

    init(requiredFailures: Int) {
        self.requiredFailures = max(1, requiredFailures)
    }

    init(defaults: UserDefaults) {
        guard defaults.bool(forKey: Self.enabledKey) else {
            self.init(requiredFailures: 1)
            return
        }
        self.init(requiredFailures: defaults.object(forKey: Self.countKey) as? Int ?? Self.defaultCount)
    }

    /// True when another check should run before the target is marked down.
    func shouldRetry(afterConsecutiveFailures failures: Int) -> Bool {
        failures < requiredFailures
    }
}
