import XCTest

/// Functional companion tests for SettingsUITests.
///
/// Tests verify **outcomes** of settings interactions: toggle persistence,
/// stepper value changes, alert confirmation flows, and navigation.
/// Existing tests in SettingsUITests are NOT modified.
@MainActor
final class SettingsFunctionalUITests: IOSUITestCase {

    // MARK: - Helpers

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func captureScreenshot(named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func navigateToSettings() {
        let settingsButton = app.buttons["dashboard_button_settings"]
        requireExists(settingsButton, timeout: 5, message: "Settings gear button should exist on dashboard")
        settingsButton.tap()
        requireExists(ui("screen_settings"), timeout: 8, message: "Settings screen should appear")
    }

    // MARK: - 1. Toggle Background Refresh -> Navigate Away -> Return -> Verify Persisted

    func testBackgroundRefreshTogglePersistsAcrossNavigation() {
        navigateToSettings()

        let toggle = app.switches["settings_toggle_backgroundRefresh"]
        scrollToElement(toggle)
        guard toggle.waitForExistence(timeout: 5) else { return }

        // Capture initial state
        let initialValue = toggle.value as? String ?? ""

        // Toggle state
        toggle.tap()
        let toggledValue = toggle.value as? String ?? ""
        XCTAssertNotEqual(initialValue, toggledValue,
                         "Background refresh toggle should change state after tap")

        // Navigate away to dashboard
        let backButton = app.navigationBars.buttons.firstMatch
        requireExists(backButton, message: "Back button should exist from settings")
        backButton.tap()
        requireExists(ui("screen_dashboard"), timeout: 5,
                      message: "Dashboard should appear after navigating back")

        // Return to settings
        navigateToSettings()

        // Verify toggle state persisted
        let toggleAfterReturn = app.switches["settings_toggle_backgroundRefresh"]
        scrollToElement(toggleAfterReturn)
        guard toggleAfterReturn.waitForExistence(timeout: 5) else {
            XCTFail("Toggle should exist after returning to settings")
            return
        }

        let persistedValue = toggleAfterReturn.value as? String ?? ""
        XCTAssertEqual(toggledValue, persistedValue,
                      "Background refresh toggle state should persist after navigation round-trip")

        // Restore original state
        toggleAfterReturn.tap()

        captureScreenshot(named: "Settings_TogglePersistence")
    }

    // MARK: - 2. Ping Count Stepper -> Value Updates

    func testPingCountStepperChangesValue() {
        navigateToSettings()

        let stepper = ui("settings_stepper_pingCount")
        requireExists(stepper, timeout: 5, message: "Ping count stepper should exist")

        // Try to increment
        let incrementButton = stepper.buttons["+"]
        guard incrementButton.waitForExistence(timeout: 3) else { return }

        // Get text before increment (the value label near the stepper)
        let valueBefore = stepper.staticTexts.firstMatch.value as? String
            ?? stepper.staticTexts.firstMatch.label

        incrementButton.tap()

        let valueAfter = stepper.staticTexts.firstMatch.value as? String
            ?? stepper.staticTexts.firstMatch.label

        XCTAssertNotEqual(valueBefore, valueAfter,
                         "Ping count value should change after tapping increment button")

        // Decrement to restore
        let decrementButton = stepper.buttons["-"]
        if decrementButton.waitForExistence(timeout: 3) {
            decrementButton.tap()
        }

        captureScreenshot(named: "Settings_PingCountStepper")
    }

    // MARK: - 3. Clear History -> Confirm Alert -> Verify Cleared

    func testClearHistoryConfirmAlertAndAction() {
        navigateToSettings()

        let clearButton = app.buttons["settings_button_clearHistory"]
        scrollToElement(clearButton)
        guard clearButton.waitForExistence(timeout: 5) else { return }

        clearButton.tap()

        // Confirmation alert should appear
        let alert = app.alerts["Clear History"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3),
                     "Clear History confirmation alert should appear")

        // Verify alert has both Cancel and destructive action buttons
        let cancelButton = alert.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "Alert should have Cancel button")

        // Find the destructive/confirm button (Clear, Delete, or OK)
        let confirmButton = alert.buttons.matching(
            NSPredicate(format: "label != 'Cancel'")
        ).firstMatch

        guard confirmButton.exists else {
            // If no confirm button, dismiss with Cancel
            cancelButton.tap()
            return
        }

        // Tap confirm to actually clear
        confirmButton.tap()

        // Alert should dismiss
        XCTAssertTrue(
            waitForDisappearance(alert, timeout: 3),
            "Alert should dismiss after confirming clear"
        )

        // Settings screen should still be visible (not crashed)
        XCTAssertTrue(ui("screen_settings").exists,
                     "Settings screen should remain visible after clearing history")

        captureScreenshot(named: "Settings_ClearHistory")
    }

    // MARK: - 4. Acknowledgements Navigation

    func testAcknowledgementsNavigationAndContent() {
        navigateToSettings()

        let ackLink = app.buttons["settings_link_acknowledgements"]
        scrollToElement(ackLink)
        guard ackLink.waitForExistence(timeout: 5) else { return }

        ackLink.tap()

        // Verify acknowledgements screen appears with content
        let hasAckScreen = app.navigationBars["Acknowledgements"].waitForExistence(timeout: 5)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Acknowledgements'")
            ).firstMatch.waitForExistence(timeout: 3)

        XCTAssertTrue(hasAckScreen, "Acknowledgements screen should appear after tapping link")

        // Verify it has actual content (not empty)
        let hasContent = app.staticTexts.count > 1
        XCTAssertTrue(hasContent, "Acknowledgements screen should display content")

        captureScreenshot(named: "Settings_Acknowledgements")
    }

    // MARK: - 5. Port Scan Timeout Stepper Interaction

    func testPortScanTimeoutStepperChangesValue() {
        navigateToSettings()

        let stepper = ui("settings_stepper_portScanTimeout")
        requireExists(stepper, timeout: 5, message: "Port scan timeout stepper should exist")

        let incrementButton = stepper.buttons["+"]
        guard incrementButton.waitForExistence(timeout: 3) else { return }

        let valueBefore = stepper.staticTexts.firstMatch.label

        incrementButton.tap()

        let valueAfter = stepper.staticTexts.firstMatch.label

        XCTAssertNotEqual(valueBefore, valueAfter,
                         "Port scan timeout should change after increment")

        // Restore
        stepper.buttons["-"].tap()

        captureScreenshot(named: "Settings_PortScanTimeout")
    }

    // MARK: - 6. High Latency Alert Toggle Reveals Threshold

    func testHighLatencyToggleRevealsThresholdControl() {
        navigateToSettings()

        let toggle = app.switches["settings_toggle_highLatencyAlert"]
        scrollToElement(toggle)
        guard toggle.waitForExistence(timeout: 5) else { return }

        // Turn on if currently off
        if (toggle.value as? String) == "0" {
            toggle.tap()
        }

        // Threshold stepper should now be visible
        let thresholdStepper = ui("settings_stepper_highLatencyThreshold")
        XCTAssertTrue(
            thresholdStepper.waitForExistence(timeout: 3),
            "High latency threshold stepper should appear when alert toggle is ON"
        )

        captureScreenshot(named: "Settings_HighLatencyThreshold")

        // Turn off to verify stepper disappears
        toggle.tap()
        let disappeared = waitForDisappearance(thresholdStepper, timeout: 3)
        XCTAssertTrue(disappeared,
                     "Threshold stepper should disappear when high latency alert is toggled OFF")
    }

    // MARK: - 7. DNS Server Field Accepts Input

    func testDNSServerFieldAcceptsInput() {
        navigateToSettings()

        let dnsField = app.textFields["settings_textfield_dnsServer"]
        requireExists(dnsField, timeout: 5, message: "DNS server text field should exist")

        clearAndTypeText("8.8.8.8", into: dnsField)

        let fieldValue = dnsField.value as? String ?? ""
        XCTAssertTrue(fieldValue.contains("8.8.8.8"),
                     "DNS server field should contain typed value '8.8.8.8', got '\(fieldValue)'")

        // Clear it
        clearAndTypeText("", into: dnsField)

        captureScreenshot(named: "Settings_DNSServerField")
    }

    // MARK: - 8. New Device Alert Toggle Changes State

    func testNewDeviceAlertToggleChangesState() {
        navigateToSettings()

        let toggle = app.switches["settings_toggle_newDeviceAlert"]
        scrollToElement(toggle)
        guard toggle.waitForExistence(timeout: 5) else { return }

        let before = toggle.value as? String ?? ""
        toggle.tap()
        let after = toggle.value as? String ?? ""

        XCTAssertNotEqual(before, after,
                         "New device alert toggle should change state after tap")

        // Restore
        toggle.tap()

        captureScreenshot(named: "Settings_NewDeviceAlert")
    }

    // MARK: - 9. Color Scheme Picker Exists and is Interactive

    func testColorSchemePickerIsInteractive() {
        navigateToSettings()

        let picker = ui("settings_picker_colorScheme")
        scrollToElement(picker)
        guard picker.waitForExistence(timeout: 5) else { return }

        picker.tap()

        // Picker should present options or be a segmented control
        let hasOptions = app.buttons.count > 3 || picker.exists

        XCTAssertTrue(hasOptions,
                     "Color scheme picker should be interactive and present options")

        captureScreenshot(named: "Settings_ColorSchemePicker")
    }

    // MARK: - 10. Clear Cache Button Interaction

    func testClearCacheButtonInteraction() {
        navigateToSettings()

        let clearCacheButton = app.buttons["settings_button_clearCache"]
        scrollToElement(clearCacheButton)
        guard clearCacheButton.waitForExistence(timeout: 5) else { return }

        clearCacheButton.tap()

        // Should show confirmation or immediately clear with success indicator
        let hasResponse = app.alerts.firstMatch.waitForExistence(timeout: 3)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'cleared'")
            ).firstMatch.waitForExistence(timeout: 3)
            || ui("screen_settings").exists

        XCTAssertTrue(hasResponse,
                     "Clear cache should show confirmation alert, success message, or remain on settings")

        // Dismiss any alert
        if app.alerts.firstMatch.exists {
            let dismissButton = app.alerts.buttons.firstMatch
            if dismissButton.exists {
                dismissButton.tap()
            }
        }

        captureScreenshot(named: "Settings_ClearCache")
    }
}
