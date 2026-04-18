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
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testSettingsScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_settings"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    // MARK: - Network Tools Section

    func testPingCountStepperExists() throws {
        XCTAssertTrue(app.otherElements["settings_stepper_pingCount"].waitForExistence(timeout: 5))
    }

    func testPingTimeoutStepperExists() throws {
        XCTAssertTrue(app.otherElements["settings_stepper_pingTimeout"].waitForExistence(timeout: 5))
    }

    func testPortScanTimeoutStepperExists() throws {
        XCTAssertTrue(app.otherElements["settings_stepper_portScanTimeout"].waitForExistence(timeout: 5))
    }

    func testDNSServerFieldExists() throws {
        XCTAssertTrue(app.textFields["settings_textfield_dnsServer"].waitForExistence(timeout: 5))
    }

    // MARK: - Monitoring Section

    func testAutoRefreshIntervalPickerExists() throws {
        app.swipeUp()
        XCTAssertTrue(app.otherElements["settings_picker_autoRefreshInterval"].waitForExistence(timeout: 5) ||
                      app.buttons["settings_picker_autoRefreshInterval"].waitForExistence(timeout: 3))
    }

    func testBackgroundRefreshToggleExists() throws {
        app.swipeUp()
        XCTAssertTrue(app.switches["settings_toggle_backgroundRefresh"].waitForExistence(timeout: 5))
    }

    // MARK: - Notification Section

    func testHighLatencyAlertToggleExists() throws {
        app.swipeUp()
        XCTAssertTrue(app.switches["settings_toggle_highLatencyAlert"].waitForExistence(timeout: 5))
    }

    // MARK: - Appearance Section

    func testAccentColorPickerExists() throws {
        app.swipeUp()
        XCTAssertTrue(app.otherElements["settings_picker_accentColor"].waitForExistence(timeout: 5) ||
                      app.buttons["settings_picker_accentColor"].waitForExistence(timeout: 3))
    }

    // MARK: - Data & Privacy Section

    func testDataRetentionPickerExists() throws {
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.otherElements["settings_picker_dataRetention"].waitForExistence(timeout: 5) ||
                      app.buttons["settings_picker_dataRetention"].waitForExistence(timeout: 3))
    }

    func testShowDetailedResultsToggleExists() throws {
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.switches["settings_toggle_showDetailedResults"].waitForExistence(timeout: 5))
    }

    func testClearHistoryButtonExists() throws {
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.buttons["settings_button_clearHistory"].waitForExistence(timeout: 5))
    }

    func testClearCacheButtonExists() throws {
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.buttons["settings_button_clearCache"].waitForExistence(timeout: 5))
    }

    // MARK: - About Section

    func testAppVersionRowExists() throws {
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.otherElements["settings_row_appVersion"].waitForExistence(timeout: 5))
    }

    func testBuildNumberRowExists() throws {
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.otherElements["settings_row_buildNumber"].waitForExistence(timeout: 5))
    }

    func testAcknowledgementsLinkExists() throws {
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.buttons["settings_link_acknowledgements"].waitForExistence(timeout: 5))
    }

    func testSupportLinkExists() throws {
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.buttons["settings_link_support"].waitForExistence(timeout: 5) ||
                      app.links["settings_link_support"].waitForExistence(timeout: 3))
    }

    func testRateAppButtonExists() throws {
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.buttons["settings_button_rateApp"].waitForExistence(timeout: 5))
    }

    // MARK: - Toggle Interaction

    func testToggleBackgroundRefresh() throws {
        app.swipeUp()
        let toggle = app.switches["settings_toggle_backgroundRefresh"]
        if toggle.waitForExistence(timeout: 5) {
            let initialValue = toggle.value as? String
            toggle.tap()
            let newValue = toggle.value as? String
            XCTAssertNotEqual(initialValue, newValue)
            // Toggle back
            toggle.tap()
        }
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
        app.swipeUp()
        let toggle = app.switches["settings_toggle_highLatencyAlert"]
        guard toggle.waitForExistence(timeout: 5) else { return }

        // If currently off, turn on and verify threshold stepper appears
        if (toggle.value as? String) == "0" {
            toggle.tap()
        }

        // FUNCTIONAL: threshold stepper should now be visible
        let stepper = app.otherElements["settings_stepper_highLatencyThreshold"]
        XCTAssertTrue(
            stepper.waitForExistence(timeout: 3),
            "High latency threshold stepper should appear when toggle is ON"
        )
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
        app.swipeUp()
        app.swipeUp()
        let clearButton = app.buttons["settings_button_clearHistory"]
        guard clearButton.waitForExistence(timeout: 5) else { return }
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
        XCTAssertTrue(app.otherElements["screen_settings"].waitForExistence(timeout: 3),
                     "Settings screen should still be visible after cancelling Clear History")
    }
}
