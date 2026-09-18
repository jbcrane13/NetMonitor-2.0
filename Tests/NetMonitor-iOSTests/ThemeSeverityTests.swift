import SwiftUI
import Testing
import NetMonitorCore
@testable import NetMonitor_iOS

struct ThemeSeverityTests {

    // MARK: - Theme.Colors.latencyColor(ms:)

    @Test func belowGoodBoundaryIsSuccess() {
        #expect(Theme.Colors.latencyColor(ms: 49) == Theme.Colors.success)
    }

    @Test func atFairBoundaryIsWarning() {
        #expect(Theme.Colors.latencyColor(ms: 50) == Theme.Colors.warning)
    }

    @Test func belowPoorBoundaryIsWarning() {
        #expect(Theme.Colors.latencyColor(ms: 149) == Theme.Colors.warning)
    }

    @Test func atPoorBoundaryIsError() {
        #expect(Theme.Colors.latencyColor(ms: 150) == Theme.Colors.error)
    }

    // MARK: - Theme.Colors.color(for:) Severity mapping

    @Test func goodMapsToSuccess() {
        #expect(Theme.Colors.color(for: .good) == Theme.Colors.success)
    }

    @Test func fairMapsToWarning() {
        #expect(Theme.Colors.color(for: .fair) == Theme.Colors.warning)
    }

    @Test func poorMapsToError() {
        #expect(Theme.Colors.color(for: .poor) == Theme.Colors.error)
    }
}
