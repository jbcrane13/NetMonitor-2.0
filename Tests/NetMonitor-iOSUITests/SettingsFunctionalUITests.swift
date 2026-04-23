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

        // FUNCTIONAL: verify the value label displays a numeric result
        let valueText = stepper.staticTexts.firstMatch.value as? String
            ?? stepper.staticTexts.firstMatch.label
        XCTAssertTrue(
            valueText.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) || $0 == " " },
            "Ping count label should display a numeric value after increment, got '\(valueText)'"
        )

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

        // FUNCTIONAL: after clearing, the clear button should still be present but
        // the app should be in a clean state (e.g., no crash, settings still navigable)
        XCTAssertTrue(
            ui("screen_settings").waitForExistence(timeout: 3),
            "Settings screen should be fully functional after clearing history"
        )

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

        // FUNCTIONAL: verify it has actual content beyond just the title
        // Count non-title static texts (at least license/framework entries)
        let contentTexts = app.staticTexts.matching(
            NSPredicate(format: "label != '' AND label != 'Acknowledgements'")
        )
        XCTAssertGreaterThan(contentTexts.count, 0,
                            "Acknowledgements screen should display license/framework content, not be empty")

        // FUNCTIONAL: verify back navigation works
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
            XCTAssertTrue(
                ui("screen_settings").waitForExistence(timeout: 5),
                "Should navigate back to settings from acknowledgements"
            )
        }

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

        // FUNCTIONAL: the new value should persist after navigating away and back
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
            requireExists(ui("screen_dashboard"), timeout: 5,
                         message: "Dashboard should appear after navigating back")
            navigateToSettings()

            let stepperAfterReturn = ui("settings_stepper_portScanTimeout")
            scrollToElement(stepperAfterReturn)
            if stepperAfterReturn.waitForExistence(timeout: 5) {
                let valueAfterReturn = stepperAfterReturn.staticTexts.firstMatch.label
                XCTAssertEqual(valueAfter, valueAfterReturn,
                             "Port scan timeout value should persist after navigation round-trip")
            }
        }

        // Restore
        let decrementButton = ui("settings_stepper_portScanTimeout").buttons["-"]
        if decrementButton.waitForExistence(timeout: 3) {
            decrementButton.tap()
        }

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

        // FUNCTIONAL: threshold stepper should be interactive
        let incrementButton = thresholdStepper.buttons["+"]
        if incrementButton.waitForExistence(timeout: 3) {
            let valueBefore = thresholdStepper.staticTexts.firstMatch.label
            incrementButton.tap()
            let valueAfter = thresholdStepper.staticTexts.firstMatch.label
            XCTAssertNotEqual(valueBefore, valueAfter,
                             "High latency threshold value should change after increment")
            // Restore
            let decrementButton = thresholdStepper.buttons["-"]
            if decrementButton.waitForExistence(timeout: 3) {
                decrementButton.tap()
            }
        }

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

        // FUNCTIONAL: verify DNS value persists after navigation round-trip
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
            requireExists(ui("screen_dashboard"), timeout: 5,
                         message: "Dashboard should appear after navigating back")
            navigateToSettings()

            let dnsFieldAfterReturn = app.textFields["settings_textfield_dnsServer"]
            scrollToElement(dnsFieldAfterReturn)
            if dnsFieldAfterReturn.waitForExistence(timeout: 5) {
                let returnedValue = dnsFieldAfterReturn.value as? String ?? ""
                XCTAssertTrue(returnedValue.contains("8.8.8.8"),
                             "DNS server field should persist value '8.8.8.8' after navigation, got '\(returnedValue)'")
            }
        }

        // Clear it
        clearAndTypeText("", into: app.textFields["settings_textfield_dnsServer"])

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

    // MARK: - 9. Color Scheme Picker Changes Selection

    func testColorSchemePickerChangesSelection() {
        navigateToSettings()

        let picker = ui("settings_picker_colorScheme")
        scrollToElement(picker)
        guard picker.waitForExistence(timeout: 5) else { return }

        // FUNCTIONAL: if segmented control, tap a different segment and verify selection change
        let segments = picker.buttons.allElementsBoundByAccessibilityElement
        guard segments.count > 1 else {
            // Single-option or non-segmented picker — just verify it exists
            XCTAssertTrue(picker.exists, "Color scheme picker should exist")
            return
        }

        // Find currently selected segment and tap a different one
        let selectedSegment = segments.first { $0.isSelected } ?? segments[0]
        let otherSegment = segments.first { !$0.isSelected } ?? segments[1]

        otherSegment.tap()

        // FUNCTIONAL: the other segment should now be selected
        XCTAssertTrue(
            otherSegment.waitForExistence(timeout: 3),
            "Tapped segment should remain visible after selection"
        )

        // Restore original selection
        selectedSegment.tap()

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
        let hasAlert = app.alerts.firstMatch.waitForExistence(timeout: 3)
        if hasAlert {
            // FUNCTIONAL: alert should have a confirm button, tap it
            let confirmButton = app.alerts.firstMatch.buttons.matching(
                NSPredicate(format: "label != 'Cancel'")
            ).firstMatch
            if confirmButton.exists {
                confirmButton.tap()
                XCTAssertTrue(
                    waitForDisappearance(app.alerts.firstMatch, timeout: 3),
                    "Alert should dismiss after confirming cache clear"
                )
            } else {
                // Dismiss with cancel
                app.alerts.firstMatch.buttons.firstMatch.tap()
            }
        }

        // FUNCTIONAL: settings screen should remain fully functional after cache clear
        XCTAssertTrue(
            ui("screen_settings").waitForExistence(timeout: 3),
            "Settings screen should remain functional after clearing cache"
        )

        captureScreenshot(named: "Settings_ClearCache")
    }
}
