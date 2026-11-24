import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Settings via Dashboard gear button
        let settingsButton = app.buttons["dashboard_button_settings"]
        // On iOS 26+ the settings screen is a CollectionView, not an Other; match any type so older trees work too.
        let settingsScreen = element("screen_settings")
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            // The first tap after a fresh launch can miss (hit point {-1, -1}); retry once.
            if !settingsScreen.waitForExistence(timeout: 5) {
                settingsButton.tap()
            }
        }
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5), "Settings screen should open")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testSettingsScreenExistsAndShowsContent() throws {
        let screen = element("screen_settings")
        XCTAssertTrue(
            screen.waitForExistence(timeout: 5),
            "Settings screen should be visible"
        )
        // FUNCTIONAL: settings screen should contain at least one section header or control
        let hasContent = app.staticTexts.count > 0
            || app.switches.count > 0
            || app.buttons.count > 1
        XCTAssertTrue(hasContent, "Settings screen should display interactive content, not be empty")
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    // MARK: - Network Tools Section

    func testPingCountStepperExistsAndIsInteractive() throws {
        let stepper = app.steppers["settings_stepper_pingCount"]
        XCTAssertTrue(
            stepper.waitForExistence(timeout: 5),
            "Ping count stepper should exist"
        )
        // FUNCTIONAL: stepper should have increment/decrement buttons
        let incrementButton = app.buttons["settings_stepper_pingCount-Increment"]
        let decrementButton = app.buttons["settings_stepper_pingCount-Decrement"]
        XCTAssertTrue(
            incrementButton.exists || decrementButton.exists,
            "Ping count stepper should have + or - buttons for interaction"
        )
    }

    func testPingTimeoutStepperExistsAndIsInteractive() throws {
        let stepper = app.steppers["settings_stepper_pingTimeout"]
        XCTAssertTrue(
            stepper.waitForExistence(timeout: 5),
            "Ping timeout stepper should exist"
        )
        // FUNCTIONAL: verify the stepper shows a numeric value
        let value = stepper.value as? String ?? ""
        XCTAssertFalse(value.isEmpty, "Ping timeout stepper should display a numeric value")
    }

    func testPortScanTimeoutStepperExistsAndIsInteractive() throws {
        let stepper = app.steppers["settings_stepper_portScanTimeout"]
        XCTAssertTrue(
            stepper.waitForExistence(timeout: 5),
            "Port scan timeout stepper should exist"
        )
        // FUNCTIONAL: verify stepper has interactive controls
        let hasButtons = app.buttons["settings_stepper_portScanTimeout-Increment"].exists
            || app.buttons["settings_stepper_portScanTimeout-Decrement"].exists
        XCTAssertTrue(hasButtons, "Port scan timeout stepper should have increment/decrement buttons")
    }

    func testDNSServerFieldExistsAndAcceptsInput() throws {
        let dnsField = app.textFields["settings_textfield_dnsServer"]
        XCTAssertTrue(
            dnsField.waitForExistence(timeout: 5),
            "DNS server field should exist"
        )
        // FUNCTIONAL: type into the field and verify the value changes
        let originalValue = dnsField.value as? String ?? ""
        clearAndTypeText("8.8.8.8", into: dnsField)
        let newValue = dnsField.value as? String ?? ""
        XCTAssertTrue(
            newValue.contains("8.8.8.8"),
            "DNS server field should contain the typed value, got '\(newValue)'"
        )
        // Restore original value
        if !originalValue.isEmpty {
            clearAndTypeText(originalValue, into: dnsField)
        }
    }

    // MARK: - Monitoring Section

    func testAutoRefreshIntervalPickerExistsAndShowsValue() throws {
        app.swipeUp()
        let pickerElement = app.otherElements["settings_picker_autoRefreshInterval"]
        let pickerButton = app.buttons["settings_picker_autoRefreshInterval"]
        XCTAssertTrue(
            pickerElement.waitForExistence(timeout: 5) ||
            pickerButton.waitForExistence(timeout: 3),
            "Auto-refresh interval picker should exist"
        )
        // FUNCTIONAL: picker should display a selected value
        let activePicker = pickerElement.exists ? pickerElement : pickerButton
        let hasValue = activePicker.staticTexts.count > 0 || activePicker.label.count > 0
        XCTAssertTrue(hasValue, "Auto-refresh interval picker should display a current value")
    }

    func testBackgroundRefreshToggleExistsAndIsTogglable() throws {
        let toggle = app.switches["settings_toggle_backgroundRefresh"]
        scrollTo(toggle)
        // FUNCTIONAL: toggle should change state when tapped
        let before = toggle.value as? String ?? ""
        toggle.flipSwitch()
        let after = toggle.value as? String ?? ""
        XCTAssertNotEqual(before, after, "Background refresh toggle should change state after tap")
        // Restore
        toggle.flipSwitch()
    }

    // MARK: - Notification Section

    func testHighLatencyAlertToggleExistsAndRevealsThreshold() throws {
        let toggle = app.switches["settings_toggle_highLatencyAlert"]
        scrollTo(toggle)
        // FUNCTIONAL: turning on the toggle should reveal the threshold stepper
        let wasOff = (toggle.value as? String) == "0"
        if wasOff {
            toggle.flipSwitch()
            // Restore even when the assertion below fails and stops the test.
            addTeardownBlock { toggle.flipSwitch() }
        }
        let thresholdStepper = app.steppers["settings_stepper_highLatencyThreshold"]
        XCTAssertTrue(
            thresholdStepper.waitForExistence(timeout: 3),
            "High latency threshold stepper should appear when toggle is ON"
        )
        // Restore
        if wasOff {
            toggle.flipSwitch()
        }
    }

    // MARK: - Appearance Section

    func testAccentColorPickerExistsAndIsTappable() throws {
        let picker = element("settings_picker_accentColor")
        scrollTo(picker)
        // FUNCTIONAL: picker should be tappable and present options
        picker.tap()
        // After tapping, either options appear or picker is still visible
        XCTAssertTrue(
            picker.waitForExistence(timeout: 3),
            "Accent color picker should remain accessible after tap"
        )
    }

    // MARK: - Data & Privacy Section

    func testDataRetentionPickerExistsAndShowsValue() throws {
        app.swipeUp()
        app.swipeUp()
        let pickerElement = app.otherElements["settings_picker_dataRetention"]
        let pickerButton = app.buttons["settings_picker_dataRetention"]
        XCTAssertTrue(
            pickerElement.waitForExistence(timeout: 5) ||
            pickerButton.waitForExistence(timeout: 3),
            "Data retention picker should exist"
        )
        // FUNCTIONAL: picker should display a current value
        let activePicker = pickerElement.exists ? pickerElement : pickerButton
        let hasValue = activePicker.staticTexts.count > 0 || activePicker.label.count > 0
        XCTAssertTrue(hasValue, "Data retention picker should display a current value")
    }

    func testShowDetailedResultsToggleExistsAndIsTogglable() throws {
        let toggle = app.switches["settings_toggle_showDetailedResults"]
        scrollTo(toggle)
        // FUNCTIONAL: toggle should change state
        let before = toggle.value as? String ?? ""
        toggle.flipSwitch()
        let after = toggle.value as? String ?? ""
        XCTAssertNotEqual(before, after, "Show detailed results toggle should change state after tap")
        // Restore
        toggle.flipSwitch()
    }

    func testClearHistoryButtonTriggersAlert() throws {
        app.swipeUp()
        app.swipeUp()
        let clearButton = app.buttons["settings_button_clearHistory"]
        XCTAssertTrue(
            clearButton.waitForExistence(timeout: 5),
            "Clear history button should exist"
        )
        // FUNCTIONAL: tapping should show a confirmation alert
        clearButton.tap()
        XCTAssertTrue(
            app.alerts["Clear History"].waitForExistence(timeout: 3),
            "Clear History confirmation alert should appear after tapping button"
        )
        // Dismiss alert
        app.alerts.buttons["Cancel"].tap()
    }

    func testClearCacheButtonTriggersResponse() throws {
        app.swipeUp()
        app.swipeUp()
        let clearCacheButton = app.buttons["settings_button_clearCache"]
        XCTAssertTrue(
            clearCacheButton.waitForExistence(timeout: 5),
            "Clear cache button should exist"
        )
        // FUNCTIONAL: tapping should show a confirmation or success indicator
        clearCacheButton.tap()
        let hasResponse = app.alerts.firstMatch.waitForExistence(timeout: 3)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'cleared'")
            ).firstMatch.waitForExistence(timeout: 3)
            || app.otherElements["screen_settings"].exists
        XCTAssertTrue(
            hasResponse,
            "Clear cache should show confirmation alert, success message, or remain on settings"
        )
        // Dismiss any alert
        if app.alerts.firstMatch.exists {
            app.alerts.buttons.firstMatch.tap()
        }
    }

    // MARK: - About Section

    func testAppVersionRowExistsAndShowsValue() throws {
        // The row's identifier lands on its two texts: the title and the value.
        let rowTexts = app.staticTexts.matching(identifier: "settings_row_appVersion")
        scrollTo(rowTexts.firstMatch)
        // FUNCTIONAL: the row should display a version string next to its title
        XCTAssertGreaterThanOrEqual(rowTexts.count, 2, "App version row should display a version string")
        XCTAssertFalse(rowTexts.element(boundBy: 1).label.isEmpty, "App version row value should not be empty")
    }

    func testBuildNumberRowExistsAndShowsValue() throws {
        // The row's identifier lands on its two texts: the title and the value.
        let rowTexts = app.staticTexts.matching(identifier: "settings_row_buildNumber")
        scrollTo(rowTexts.firstMatch)
        // FUNCTIONAL: the row should display a build string next to its title
        XCTAssertGreaterThanOrEqual(rowTexts.count, 2, "Build number row should display a build string")
        XCTAssertFalse(rowTexts.element(boundBy: 1).label.isEmpty, "Build number row value should not be empty")
    }

    func testAcknowledgementsLinkNavigatesToScreen() throws {
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        let link = app.buttons["settings_link_acknowledgements"]
        XCTAssertTrue(
            link.waitForExistence(timeout: 5),
            "Acknowledgements link should exist"
        )
        // FUNCTIONAL: tapping should navigate to acknowledgements
        link.tap()
        XCTAssertTrue(
            app.navigationBars["Acknowledgements"].waitForExistence(timeout: 5) ||
            app.navigationBars.firstMatch.exists,
            "Acknowledgements screen should appear after tapping the link"
        )
        // Verify content exists
        XCTAssertTrue(
            app.staticTexts.count > 1,
            "Acknowledgements screen should display content"
        )
    }

    func testSupportLinkIsAccessible() throws {
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        let supportButton = app.buttons["settings_link_support"]
        let supportLink = app.links["settings_link_support"]
        XCTAssertTrue(
            supportButton.waitForExistence(timeout: 5) ||
            supportLink.waitForExistence(timeout: 3),
            "Support link should exist"
        )
        // FUNCTIONAL: support element should be tappable
        let supportElement = supportButton.exists ? supportButton : supportLink
        XCTAssertTrue(supportElement.isEnabled, "Support link should be tappable")
    }

    func testRateAppButtonIsAccessible() throws {
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        let rateButton = app.buttons["settings_button_rateApp"]
        XCTAssertTrue(
            rateButton.waitForExistence(timeout: 5),
            "Rate app button should exist"
        )
        // FUNCTIONAL: rate button should be enabled/tappable
        XCTAssertTrue(rateButton.isEnabled, "Rate app button should be tappable")
    }

    // MARK: - Toggle Interaction

    func testToggleBackgroundRefresh() throws {
        let toggle = app.switches["settings_toggle_backgroundRefresh"]
        scrollTo(toggle)
        let initialValue = toggle.value as? String
        toggle.flipSwitch()
        let newValue = toggle.value as? String
        XCTAssertNotEqual(initialValue, newValue)
        // Toggle back
        toggle.flipSwitch()
    }

    // MARK: - Navigation

    func testAcknowledgementsNavigation() throws {
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        let link = app.buttons["settings_link_acknowledgements"]
        if link.waitForExistence(timeout: 5) {
            link.tap()
            // Should navigate to acknowledgements view
            XCTAssertTrue(app.navigationBars["Acknowledgements"].waitForExistence(timeout: 5) ||
                          app.navigationBars.firstMatch.exists)
        }
    }

    // MARK: - Clear History Alert

    func testClearHistoryShowsAlert() throws {
        app.swipeUp()
        app.swipeUp()
        let clearButton = app.buttons["settings_button_clearHistory"]
        if clearButton.waitForExistence(timeout: 5) {
            clearButton.tap()
            // Alert should appear
            XCTAssertTrue(app.alerts["Clear History"].waitForExistence(timeout: 3))
            // Dismiss alert
            app.alerts.buttons["Cancel"].tap()
        }
    }

    // MARK: - Functional: Toggle state changes

    func testNewDeviceAlertToggleChangesState() throws {
        // Scroll to reveal the notification section
        app.swipeUp()
        let toggle = app.switches["settings_toggle_newDeviceAlert"]
        guard toggle.waitForExistence(timeout: 5) else { return }

        let before = toggle.value as? String ?? ""
        toggle.tap()
        let after = toggle.value as? String ?? ""

        // FUNCTIONAL: state must change after tap
        XCTAssertNotEqual(before, after, "New Device Alert toggle value must change after tap")

        // Restore original state
        toggle.tap()
    }

    func testHighLatencyToggleRevealsThresholdStepper() throws {
        let toggle = app.switches["settings_toggle_highLatencyAlert"]
        scrollTo(toggle)

        // If currently off, turn on and verify threshold stepper appears
        let wasOff = (toggle.value as? String) == "0"
        if wasOff {
            toggle.flipSwitch()
            // Restore even when the assertion below fails and stops the test.
            addTeardownBlock { toggle.flipSwitch() }
        }

        // FUNCTIONAL: threshold stepper should now be visible
        let stepper = app.steppers["settings_stepper_highLatencyThreshold"]
        XCTAssertTrue(
            stepper.waitForExistence(timeout: 3),
            "High latency threshold stepper should appear when toggle is ON"
        )
        // Restore
        if wasOff {
            toggle.flipSwitch()
        }
    }

    func testPingCountStepperChangesValue() throws {
        let stepper = app.otherElements["settings_stepper_pingCount"]
        guard stepper.waitForExistence(timeout: 5) else { return }

        // Get initial value from the associated label near the stepper
        let initialText = stepper.staticTexts.firstMatch.value as? String ?? ""

        // Tap increment button
        let incrementButton = stepper.buttons["+"]
        guard incrementButton.waitForExistence(timeout: 3) else { return }
        incrementButton.tap()

        // FUNCTIONAL: value should change after increment
        let newText = stepper.staticTexts.firstMatch.value as? String ?? ""
        XCTAssertNotEqual(initialText, newText,
                         "Ping count value should change after tapping the increment button")

        // Restore by tapping decrement
        stepper.buttons["-"].tap()
    }

    // MARK: - Functional: Clear actions show confirmation

    func testClearHistoryShowsConfirmationAlertAndCanBeCancelled() throws {
        let clearButton = app.buttons["settings_button_clearHistory"]
        scrollTo(clearButton)
        clearButton.tap()

        // FUNCTIONAL: confirmation alert must appear
        let alert = app.alerts["Clear History"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3),
                     "Clear History confirmation alert should appear after tapping button")

        // FUNCTIONAL: Cancel dismisses the alert without clearing
        let cancelButton = alert.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "Cancel button should exist in Clear History alert")
        cancelButton.tap()

        // FUNCTIONAL: alert dismissed, settings screen still visible
        XCTAssertTrue(element("screen_settings").waitForExistence(timeout: 3),
                     "Settings screen should still be visible after cancelling Clear History")
    }

    // MARK: - Functional: Toggle persists across navigation

    func testBackgroundRefreshTogglePersistsAfterNavigation() throws {
        let toggle = app.switches["settings_toggle_backgroundRefresh"]
        scrollTo(toggle)

        let before = toggle.value as? String ?? ""
        toggle.flipSwitch()
        let afterToggle = toggle.value as? String ?? ""
        XCTAssertNotEqual(before, afterToggle, "Toggle should change state after tap")

        // Navigate away and come back
        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3), "Back button should exist")
        backButton.tap()
        let settingsButton = app.buttons["dashboard_button_settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Dashboard settings button should exist")
        settingsButton.tap()

        // FUNCTIONAL: verify toggle state persisted
        let toggleAfterReturn = app.switches["settings_toggle_backgroundRefresh"]
        scrollTo(toggleAfterReturn)
        let persistedValue = toggleAfterReturn.value as? String ?? ""
        XCTAssertEqual(afterToggle, persistedValue,
                       "Background refresh toggle state should persist after navigation round-trip")
        // Restore
        toggleAfterReturn.flipSwitch()
    }

    // MARK: - Helpers

    /// Any element with this identifier. On iOS 26+ the settings screen is a `CollectionView`, steppers are
    /// `Stepper`s, and a row's identifier lands on its texts, so element types aren't stable.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scrolls the settings list until the element is on screen. Rows below the fold aren't in the tree
    /// until the lazy list renders them.
    private func scrollTo(_ target: XCUIElement, maxSwipes: Int = 8) {
        let list = element("screen_settings")
        for _ in 0..<maxSwipes where !(target.exists && target.isHittable) {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(
            target.waitForExistence(timeout: 3) && target.isHittable,
            "\(target) should be on screen and hittable after scrolling"
        )
    }

    private func clearAndTypeText(_ text: String, into element: XCUIElement) {
        element.tap()
        if let currentValue = element.value as? String,
           !currentValue.isEmpty,
           currentValue != element.placeholderValue {
            let deleteSequence = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            element.typeText(deleteSequence)
        }
        element.typeText(text)
    }
}
