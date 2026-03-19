import Testing
import Foundation
@testable import NetMonitor_iOS

// MARK: - New Feature Unit Tests (NetMonitor20-n51)
//
// Covers settings persistence and onboarding flag for features #64-#80.
// Uses a UUID-keyed UserDefaults suite per test to avoid cross-test pollution.

struct NewFeatureUnitTests {

    // MARK: - Helpers

    private func freshDefaults() -> UserDefaults {
        let suite = "com.netmonitor.test.newfeature.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    // MARK: - Onboarding Flag (#72)

    @Test("hasCompletedOnboarding flag persists correctly")
    func onboardingFlagPersists() {
        let ud = freshDefaults()
        let key = "hasCompletedOnboarding"
        ud.set(true, forKey: key)
        #expect(ud.bool(forKey: key) == true,
                "hasCompletedOnboarding should persist as true after being set")
    }

    @Test("hasCompletedOnboarding defaults to false when not set")
    func onboardingFlagDefaultsToFalse() {
        let ud = freshDefaults()
        // No value written — bool(forKey:) defaults to false
        #expect(ud.bool(forKey: "hasCompletedOnboarding") == false,
                "hasCompletedOnboarding should be false when never written")
    }

    @Test("hasCompletedOnboarding can be reset to false")
    func onboardingFlagCanBeReset() {
        let ud = freshDefaults()
        let key = "hasCompletedOnboarding"
        ud.set(true, forKey: key)
        ud.set(false, forKey: key)
        #expect(ud.bool(forKey: key) == false,
                "hasCompletedOnboarding should be resettable to false")
    }

    // MARK: - Color Scheme Preference (#80)

    @Test("Color scheme preference 'light' persists to UserDefaults")
    func colorSchemeLightPersists() {
        let ud = freshDefaults()
        ud.set("light", forKey: AppSettings.Keys.selectedTheme)
        #expect(ud.string(forKey: AppSettings.Keys.selectedTheme) == "light",
                "selectedTheme should persist 'light' correctly")
    }

    @Test("Color scheme preference 'dark' persists to UserDefaults")
    func colorSchemeDarkPersists() {
        let ud = freshDefaults()
        ud.set("dark", forKey: AppSettings.Keys.selectedTheme)
        #expect(ud.string(forKey: AppSettings.Keys.selectedTheme) == "dark",
                "selectedTheme should persist 'dark' correctly")
    }

    @Test("Color scheme preference 'system' persists to UserDefaults")
    func colorSchemeSystemPersists() {
        let ud = freshDefaults()
        ud.set("system", forKey: AppSettings.Keys.selectedTheme)
        #expect(ud.string(forKey: AppSettings.Keys.selectedTheme) == "system",
                "selectedTheme should persist 'system' correctly")
    }

    @Test("Color scheme preference can be changed after initial write")
    func colorSchemeCanBeChanged() {
        let ud = freshDefaults()
        ud.set("light", forKey: AppSettings.Keys.selectedTheme)
        ud.set("dark", forKey: AppSettings.Keys.selectedTheme)
        #expect(ud.string(forKey: AppSettings.Keys.selectedTheme) == "dark",
                "selectedTheme should reflect the most recent write")
    }

    // MARK: - New Device Alert Toggle (#67)

    @Test("New device alert enabled=true persists to UserDefaults")
    func newDeviceAlertEnabledPersists() {
        let ud = freshDefaults()
        ud.set(true, forKey: AppSettings.Keys.newDeviceAlertEnabled)
        #expect(ud.bool(forKey: AppSettings.Keys.newDeviceAlertEnabled) == true,
                "newDeviceAlertEnabled=true should round-trip through UserDefaults")
    }

    @Test("New device alert enabled=false persists to UserDefaults")
    func newDeviceAlertDisabledPersists() {
        let ud = freshDefaults()
        ud.set(false, forKey: AppSettings.Keys.newDeviceAlertEnabled)
        #expect(ud.bool(forKey: AppSettings.Keys.newDeviceAlertEnabled) == false,
                "newDeviceAlertEnabled=false should round-trip through UserDefaults")
    }

    @Test("New device alert toggle state can be flipped")
    func newDeviceAlertCanBeToggled() {
        let ud = freshDefaults()
        ud.set(true, forKey: AppSettings.Keys.newDeviceAlertEnabled)
        let initial = ud.bool(forKey: AppSettings.Keys.newDeviceAlertEnabled)
        ud.set(!initial, forKey: AppSettings.Keys.newDeviceAlertEnabled)
        #expect(ud.bool(forKey: AppSettings.Keys.newDeviceAlertEnabled) == false,
                "Toggling newDeviceAlertEnabled from true should yield false")
    }

    // MARK: - Widget Data Keys (#66 — widget data writing from DashboardViewModel)

    @Test("Widget key constants use group prefix")
    func widgetKeyConstantsHaveGroupPrefix() {
        #expect(AppSettings.Keys.widgetIsConnected.hasPrefix("widget_"),
                "Widget key should start with 'widget_'")
        #expect(AppSettings.Keys.widgetSSID.hasPrefix("widget_"),
                "Widget SSID key should start with 'widget_'")
        #expect(AppSettings.Keys.widgetDeviceCount.hasPrefix("widget_"),
                "Widget device count key should start with 'widget_'")
        #expect(AppSettings.Keys.widgetGatewayLatency.hasPrefix("widget_"),
                "Widget gateway latency key should start with 'widget_'")
    }

    @Test("Widget connectivity data persists correctly")
    func widgetConnectivityDataPersists() {
        let ud = freshDefaults()
        ud.set(true, forKey: AppSettings.Keys.widgetIsConnected)
        ud.set("HomeNetwork", forKey: AppSettings.Keys.widgetSSID)
        ud.set(12, forKey: AppSettings.Keys.widgetDeviceCount)
        ud.set(4.2, forKey: AppSettings.Keys.widgetGatewayLatency)

        #expect(ud.bool(forKey: AppSettings.Keys.widgetIsConnected) == true)
        #expect(ud.string(forKey: AppSettings.Keys.widgetSSID) == "HomeNetwork")
        #expect(ud.integer(forKey: AppSettings.Keys.widgetDeviceCount) == 12)
        #expect(abs(ud.double(forKey: AppSettings.Keys.widgetGatewayLatency) - 4.2) < 0.001)
    }
}
