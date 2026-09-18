import Testing
@testable import NetMonitorCore

struct NetworkHealthSeverityTests {

    // MARK: - latencySeverity(ms:)

    @Test("49ms is good")
    func latency49IsGood() {
        #expect(NetworkHealthScore.latencySeverity(ms: 49) == .good)
    }

    @Test("50ms is fair")
    func latency50IsFair() {
        #expect(NetworkHealthScore.latencySeverity(ms: 50) == .fair)
    }

    @Test("149ms is fair")
    func latency149IsFair() {
        #expect(NetworkHealthScore.latencySeverity(ms: 149) == .fair)
    }

    @Test("150ms is poor")
    func latency150IsPoor() {
        #expect(NetworkHealthScore.latencySeverity(ms: 150) == .poor)
    }

    // MARK: - signalSeverity(percent:)

    @Test("40% is poor")
    func signal40IsPoor() {
        #expect(NetworkHealthScore.signalSeverity(percent: 40) == .poor)
    }

    @Test("41% is fair")
    func signal41IsFair() {
        #expect(NetworkHealthScore.signalSeverity(percent: 41) == .fair)
    }

    @Test("70% is fair")
    func signal70IsFair() {
        #expect(NetworkHealthScore.signalSeverity(percent: 70) == .fair)
    }

    @Test("71% is good")
    func signal71IsGood() {
        #expect(NetworkHealthScore.signalSeverity(percent: 71) == .good)
    }
}
