import XCTest

/// Verifies macOS Settings preferences actually persist across app launches.
///
/// Existing `SettingsUITests` and `SettingsFunctionalUITests` only verify that
/// toggles/sliders change their *in-memory* value when tapped. These tests go a
/// step further: change a preference via UI, terminate the app, relaunch it,
/// navigate back to the setting, and assert the new value is still present.
///
/// This closes the gap described in PRD-issue-174:
/// "Settings: verify preference changes persist".
@MainActor
final class SettingsPersistenceUITests: MacOSUITestCase {

    // MARK: - Helpers

    /// Tap a settings tab by its logical name. Source of truth is
    /// `SettingsView`'s identifier `settings_tab_<RawValue>` (CapitalCase), but
    /// we also try lowercase + plain cell/button lookup in case the underlying
    /// element hierarchy changes.
    private func tapSettingsTab(_ rawValue: String) {
        let candidates: [XCUIElement] = [
            ui("settings_tab_\(rawValue)"),
            ui("settings_tab_\(rawValue.lowercased())"),
            app.staticTexts[rawValue],
            app.outlines.staticTexts[rawValue]
        ]
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 2) {
                candidate.tap()
                return
            }
        }
        XCTFail("Settings tab '\(rawValue)' could not be located")
    }

    /// Relaunch the app while keeping UserDefaults intact so persistence is
    /// exercised end-to-end.
    private func relaunchApp() {
        app.terminate()
        // NOTE: create a fresh XCUIApplication to avoid carrying any cached
        // element hierarchy across the restart.
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["XCUITest"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "Main window should appear after relaunch")
        navigateToSidebar("settings")
    }

    /// Toggle a checkbox and return (oldValue, newValue). No-op if it doesn't
    /// exist.
    @discardableResult
    private func flip(checkbox id: String, timeout: TimeInterval = 3) -> (String, String)? {
        let box = app.checkBoxes[id]
        guard box.waitForExistence(timeout: timeout) else { return nil }
        let before = (box.value as? String) ?? ""
        box.tap()
        let after = (box.value as? String) ?? ""
        XCTAssertNotEqual(before, after,
                          "Checkbox '\(id)' should toggle after tap (was '\(before)')")
        return (before, after)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        navigateToSidebar("settings")
    }

    // MARK: - General Tab: Show in Dock

    func testShowInDockPersistsAcrossRelaunch() {
        tapSettingsTab("General")

        guard let (_, valueAfterToggle) = flip(checkbox: "settings_toggle_showInDock") else {
            XCTFail("Show in Dock checkbox not found")
            return
        }

        relaunchApp()
        tapSettingsTab("General")

        let afterRelaunch = requireExists(
            app.checkBoxes["settings_toggle_showInDock"], timeout: 5,
            message: "Show in Dock checkbox should exist after relaunch"
        )
        XCTAssertEqual(afterRelaunch.value as? String, valueAfterToggle,
                       "Show in Dock preference should persist across app launches")

        // Restore original state so the test is idempotent for the next run.
        afterRelaunch.tap()

        captureScreenshot(named: "MacSettings_ShowInDock_Persisted")
    }

    // MARK: - General Tab: Show in Menu Bar

    func testShowInMenuBarPersistsAcrossRelaunch() {
        tapSettingsTab("General")

        guard let (_, valueAfterToggle) = flip(checkbox: "settings_toggle_showInMenuBar") else {
            XCTFail("Show in Menu Bar checkbox not found")
            return
        }

        relaunchApp()
        tapSettingsTab("General")

        let afterRelaunch = requireExists(
            app.checkBoxes["settings_toggle_showInMenuBar"], timeout: 5,
            message: "Show in Menu Bar checkbox should exist after relaunch"
        )
        XCTAssertEqual(afterRelaunch.value as? String, valueAfterToggle,
                       "Show in Menu Bar preference should persist across app launches")

        afterRelaunch.tap()
    }

    // MARK: - Monitoring Tab: Retry Enabled

    func testRetryEnabledPersistsAcrossRelaunch() {
        tapSettingsTab("Monitoring")

        guard let (_, valueAfterToggle) = flip(checkbox: "settings_toggle_retryEnabled") else {
            XCTFail("Retry enabled checkbox not found")
            return
        }

        relaunchApp()
        tapSettingsTab("Monitoring")

        let afterRelaunch = requireExists(
            app.checkBoxes["settings_toggle_retryEnabled"], timeout: 5,
            message: "Retry enabled checkbox should exist after relaunch"
        )
        XCTAssertEqual(afterRelaunch.value as? String, valueAfterToggle,
                       "Retry enabled preference should persist across app launches")

        afterRelaunch.tap()
    }

    // MARK: - Notifications Tab: Notifications Enabled

    func testNotificationsEnabledPersistsAcrossRelaunch() {
        tapSettingsTab("Notifications")

        guard let (_, valueAfterToggle) = flip(checkbox: "settings_toggle_notificationsEnabled") else {
            XCTFail("Notifications enabled checkbox not found")
            return
        }

        relaunchApp()
        tapSettingsTab("Notifications")

        let afterRelaunch = requireExists(
            app.checkBoxes["settings_toggle_notificationsEnabled"], timeout: 5,
            message: "Notifications enabled checkbox should exist after relaunch"
        )
        XCTAssertEqual(afterRelaunch.value as? String, valueAfterToggle,
                       "Notifications enabled preference should persist across app launches")

        afterRelaunch.tap()
    }

    // MARK: - Notifications Tab: Latency Threshold Slider

    func testLatencyThresholdSliderPersistsAcrossRelaunch() {
        tapSettingsTab("Notifications")

        // Notifications must be on for the slider to be enabled.
        let notificationsToggle = app.checkBoxes["settings_toggle_notificationsEnabled"]
        if notificationsToggle.waitForExistence(timeout: 3),
           (notificationsToggle.value as? String) == "0" {
            notificationsToggle.tap()
        }

        let slider = app.sliders["settings_slider_latencyThreshold"]
        guard slider.waitForExistence(timeout: 3) else {
            XCTFail("Latency threshold slider not found")
            return
        }

        let before = slider.normalizedSliderPosition
        // Pick a target that is meaningfully different from before to avoid
        // noise when the slider happens to already be at the target.
        let target = before < 0.5 ? 0.8 : 0.2
        slider.adjust(toNormalizedSliderPosition: target)
        let adjusted = slider.normalizedSliderPosition

        relaunchApp()
        tapSettingsTab("Notifications")

        let afterRelaunch = requireExists(
            app.sliders["settings_slider_latencyThreshold"], timeout: 5,
            message: "Latency slider should exist after relaunch"
        )
        let persisted = afterRelaunch.normalizedSliderPosition

        // Slider values snap to the step size (50ms over a 100...1000 range =
        // 18 discrete positions → ~0.056 per step), so allow a small tolerance.
        XCTAssertEqual(persisted, adjusted, accuracy: 0.1,
                       "Latency threshold should persist across relaunch (expected near \(adjusted), got \(persisted))")
    }

    // MARK: - Network Tab: Use System Proxy

    func testUseSystemProxyPersistsAcrossRelaunch() {
        tapSettingsTab("Network")

        guard let (_, valueAfterToggle) = flip(checkbox: "settings_toggle_useSystemProxy") else {
            XCTFail("Use system proxy checkbox not found")
            return
        }

        relaunchApp()
        tapSettingsTab("Network")

        let afterRelaunch = requireExists(
            app.checkBoxes["settings_toggle_useSystemProxy"], timeout: 5,
            message: "Use system proxy checkbox should exist after relaunch"
        )
        XCTAssertEqual(afterRelaunch.value as? String, valueAfterToggle,
                       "Use system proxy preference should persist across app launches")

        afterRelaunch.tap()
    }

    // MARK: - Appearance Tab: Compact Mode

    func testCompactModePersistsAcrossRelaunch() {
        tapSettingsTab("Appearance")

        guard let (_, valueAfterToggle) = flip(checkbox: "settings_toggle_compactMode") else {
            XCTFail("Compact mode checkbox not found")
            return
        }

        relaunchApp()
        tapSettingsTab("Appearance")

        let afterRelaunch = requireExists(
            app.checkBoxes["settings_toggle_compactMode"], timeout: 5,
            message: "Compact mode checkbox should exist after relaunch"
        )
        XCTAssertEqual(afterRelaunch.value as? String, valueAfterToggle,
                       "Compact mode preference should persist across app launches")

        afterRelaunch.tap()

        captureScreenshot(named: "MacSettings_CompactMode_Persisted")
    }

    // MARK: - Companion Tab: Companion Enabled

    func testCompanionEnabledPersistsAcrossRelaunch() {
        tapSettingsTab("Companion")

        guard let (_, valueAfterToggle) = flip(checkbox: "settings_toggle_companionEnabled") else {
            XCTFail("Companion enabled checkbox not found")
            return
        }

        relaunchApp()
        tapSettingsTab("Companion")

        let afterRelaunch = requireExists(
            app.checkBoxes["settings_toggle_companionEnabled"], timeout: 5,
            message: "Companion enabled checkbox should exist after relaunch"
        )
        XCTAssertEqual(afterRelaunch.value as? String, valueAfterToggle,
                       "Companion enabled preference should persist across app launches")

        afterRelaunch.tap()
    }

    // MARK: - Notify Target Down

    func testNotifyTargetDownPersistsAcrossRelaunch() {
        tapSettingsTab("Notifications")

        // Make sure notifications are enabled so sub-toggles are interactive.
        let notificationsToggle = app.checkBoxes["settings_toggle_notificationsEnabled"]
        if notificationsToggle.waitForExistence(timeout: 3),
           (notificationsToggle.value as? String) == "0" {
            notificationsToggle.tap()
        }

        guard let (_, valueAfterToggle) = flip(checkbox: "settings_toggle_notifyTargetDown") else {
            XCTFail("Notify target down checkbox not found")
            return
        }

        relaunchApp()
        tapSettingsTab("Notifications")

        let afterRelaunch = requireExists(
            app.checkBoxes["settings_toggle_notifyTargetDown"], timeout: 5,
            message: "Notify target down checkbox should exist after relaunch"
        )
        XCTAssertEqual(afterRelaunch.value as? String, valueAfterToggle,
                       "Notify target down preference should persist across app launches")

        afterRelaunch.tap()
    }

    // MARK: - Notify Target Recovery

    func testNotifyTargetRecoveryPersistsAcrossRelaunch() {
        tapSettingsTab("Notifications")

        let notificationsToggle = app.checkBoxes["settings_toggle_notificationsEnabled"]
        if notificationsToggle.waitForExistence(timeout: 3),
           (notificationsToggle.value as? String) == "0" {
            notificationsToggle.tap()
        }

        guard let (_, valueAfterToggle) = flip(checkbox: "settings_toggle_notifyTargetRecovery") else {
            XCTFail("Notify target recovery checkbox not found")
            return
        }

        relaunchApp()
        tapSettingsTab("Notifications")

        let afterRelaunch = requireExists(
            app.checkBoxes["settings_toggle_notifyTargetRecovery"], timeout: 5,
            message: "Notify target recovery checkbox should exist after relaunch"
        )
        XCTAssertEqual(afterRelaunch.value as? String, valueAfterToggle,
                       "Notify target recovery preference should persist across app launches")

        afterRelaunch.tap()
    }
}
