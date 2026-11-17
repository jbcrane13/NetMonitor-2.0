import Foundation
import Testing
@testable import NetMonitorCore

@Suite("NotificationService alert defaults")
struct NotificationAlertDefaultsTests {
    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "NotificationAlertDefaultsTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite) ?? .standard, suite)
    }

    @Test func targetDownAlertIsOnForFreshInstall() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(NotificationService.isTargetDownAlertEnabled(in: defaults))
    }

    @Test func newDeviceAlertIsOnForFreshInstall() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(NotificationService.isNewDeviceAlertEnabled(in: defaults))
    }

    @Test func alertsStayOffWhenTheUserTurnsThemOff() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "targetDownAlertEnabled")
        defaults.set(false, forKey: "newDeviceAlertEnabled")
        #expect(!NotificationService.isTargetDownAlertEnabled(in: defaults))
        #expect(!NotificationService.isNewDeviceAlertEnabled(in: defaults))
    }

    @Test func alertsStayOnWhenTheUserTurnsThemOn() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "targetDownAlertEnabled")
        defaults.set(true, forKey: "newDeviceAlertEnabled")
        #expect(NotificationService.isTargetDownAlertEnabled(in: defaults))
        #expect(NotificationService.isNewDeviceAlertEnabled(in: defaults))
    }
}
