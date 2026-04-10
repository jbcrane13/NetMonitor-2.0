import Testing
@testable import NetworkScanKit

struct ThermalThrottleMonitorTests {

    @Test("multiplier is one of the expected values")
    func multiplierValidValue() {
        let m = ThermalThrottleMonitor.shared.multiplier
        let validValues = [0.25, 0.5, 1.0]
        #expect(validValues.contains(m))
    }

    @Test("effectiveLimit returns at least 1 for zero base")
    func effectiveLimitNeverZero() {
        let limit = ThermalThrottleMonitor.shared.effectiveLimit(from: 0)
        #expect(limit >= 1)
    }

    @Test("effectiveLimit returns at least 1 for any base")
    func effectiveLimitMinimumOne() {
        for base in [1, 2, 4, 10, 60, 100] {
            let limit = ThermalThrottleMonitor.shared.effectiveLimit(from: base)
            #expect(limit >= 1)
        }
    }

    @Test("effectiveLimit is consistent with multiplier")
    func effectiveLimitConsistentWithMultiplier() {
        let monitor = ThermalThrottleMonitor.shared
        let base = 60
        let expected = max(1, Int(Double(base) * monitor.multiplier))
        #expect(monitor.effectiveLimit(from: base) == expected)
    }

    @Test("effectiveLimit does not exceed base when multiplier is 1.0")
    func effectiveLimitDoesNotExceedBase() {
        let monitor = ThermalThrottleMonitor.shared
        let base = 60
        let limit = monitor.effectiveLimit(from: base)
        // Effective limit is always <= base (multiplier <= 1.0)
        #expect(limit <= base)
    }
}
