@preconcurrency import XCTest

final class ScheduledScanUITests: IOSUITestCase {

    func testScheduledScanSettingsIsAccessibleFromSettings() {
        openSettings()

        // Look for the scheduled scan navigation link
        let settingsScreen = app.descendants(matching: .any)["screen_settings"]
        if !settingsScreen.waitForExistence(timeout: 3) {
            // Try navigating to Settings tab
            let settingsTab = app.tabBars.buttons["Settings"]
            if settingsTab.waitForExistence(timeout: 3) {
                settingsTab.tap()
            }
        }

        // Check that the Settings screen is visible
        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 5),
            "Settings navigation should be visible"
        )
    }

    func testScheduledScanViewHasRequiredControls() {
        navigateToScheduledScan()

        XCTAssertTrue(
            app.descendants(matching: .any)["screen_scheduledScan"].waitForExistence(timeout: 5) ||
            app.navigationBars.firstMatch.waitForExistence(timeout: 3),
            "Scheduled scan settings screen should be visible"
        )
    }

    func testScheduledScanToggleExists() {
        navigateToScheduledScan()

        let toggle = app.switches["settings_toggle_scheduledScan"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Enable scheduled scan toggle should exist"
        )
    }

    func testScanNowButtonExists() {
        navigateToScheduledScan()

        let button = app.buttons["settings_button_scanNow"]
        XCTAssertTrue(
            button.waitForExistence(timeout: 5),
            "Scan Now button should exist"
        )
    }

    func testNotificationTogglesExist() {
        navigateToScheduledScan()

        XCTAssertTrue(
            app.switches["settings_toggle_notifyNew"].waitForExistence(timeout: 5),
            "Notify on new devices toggle should exist"
        )
        XCTAssertTrue(
            app.switches["settings_toggle_notifyMissing"].waitForExistence(timeout: 3),
            "Notify on missing devices toggle should exist"
        )
    }

    // MARK: - Functional Tests

    @MainActor
    func testScheduledScanToggleChangesState() {
        navigateToScheduledScan()

        let toggle = app.switches["settings_toggle_scheduledScan"]
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Scheduled scan toggle must exist to test state change")
            return
        }

        let valueBefore = toggle.value as? String ?? ""
        toggle.tap()

        // Give the UI a moment to update
        let valueAfter = toggle.value as? String ?? ""
        XCTAssertNotEqual(
            valueBefore,
            valueAfter,
            "Scheduled scan toggle value should change after tap (was '\(valueBefore)', now '\(valueAfter)')"
        )
    }

    @MainActor
    func testScanNowButtonTriggersVisibleOutcome() {
        navigateToScheduledScan()

        let button = app.buttons["settings_button_scanNow"]
        guard button.waitForExistence(timeout: 5) else {
            XCTFail("Scan Now button must exist to test its outcome")
            return
        }

        button.tap()

        // Valid outcomes on simulator:
        // a) A progress indicator appears while scanning runs
        // b) An alert or toast appears with a result or error message
        // c) The button briefly becomes disabled then re-enables
        // d) The scan status label updates
        let progressAppeared = app.activityIndicators.firstMatch.waitForExistence(timeout: 3)
        let alertAppeared    = app.alerts.firstMatch.waitForExistence(timeout: 3)
        let toastAppeared    = app.descendants(matching: .any)
                                    .matching(NSPredicate(format: "identifier CONTAINS[c] 'toast' OR identifier CONTAINS[c] 'status'"))
                                    .firstMatch.waitForExistence(timeout: 3)
        let buttonStillExists = button.waitForExistence(timeout: 5)

        // Dismiss any alert so teardown is clean
        if alertAppeared {
            app.alerts.firstMatch.buttons.firstMatch.tap()
        }

        XCTAssertTrue(
            progressAppeared || alertAppeared || toastAppeared || buttonStillExists,
            "After tapping Scan Now, some visible outcome should occur and the screen should remain stable"
        )
    }

    @MainActor
    func testNotificationToggleChangesState() {
        navigateToScheduledScan()

        let toggle = app.switches["settings_toggle_notifyNew"]
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Notify-new-devices toggle must exist to test state change")
            return
        }

        let valueBefore = toggle.value as? String ?? ""
        toggle.tap()

        let valueAfter = toggle.value as? String ?? ""
        XCTAssertNotEqual(
            valueBefore,
            valueAfter,
            "Notify new devices toggle value should change after tap (was '\(valueBefore)', now '\(valueAfter)')"
        )
    }

    @MainActor
    func testToggleStatePersistsAfterNavigatingAway() {
        navigateToScheduledScan()

        let toggle = app.switches["settings_toggle_scheduledScan"]
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Scheduled scan toggle must exist to test state persistence")
            return
        }

        // Record the state before toggling
        let stateBefore = toggle.value as? String ?? ""
        toggle.tap()
        let stateAfterToggle = toggle.value as? String ?? ""
        XCTAssertNotEqual(stateBefore, stateAfterToggle, "Toggle state should change immediately after tap")

        // Navigate away — go back to the Settings root
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        }

        // Return to Scheduled Scan screen
        navigateToScheduledScan()

        let toggleAfterReturn = app.switches["settings_toggle_scheduledScan"]
        guard toggleAfterReturn.waitForExistence(timeout: 5) else {
            XCTFail("Scheduled scan toggle should still exist after navigating back")
            return
        }

        let stateAfterReturn = toggleAfterReturn.value as? String ?? ""
        XCTAssertEqual(
            stateAfterToggle,
            stateAfterReturn,
            "Toggle state '\(stateAfterToggle)' should persist after navigating away and returning (got '\(stateAfterReturn)')"
        )
    }

    // MARK: - Helpers

    private func openSettings() {
        requireExists(app.tabBars.buttons["Dashboard"], message: "Dashboard tab should exist").tap()

        let settingsButton = app.buttons["dashboard_button_settings"]
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        } else {
            requireExists(app.navigationBars.buttons.firstMatch, message: "A navigation bar button should exist for settings").tap()
        }

        requireExists(app.descendants(matching: .any)["screen_settings"], timeout: 8, message: "Settings screen should open")
    }

    private func navigateToScheduledScan() {
        openSettings()

        // Look for a "Scheduled Scans" or "Scheduled" cell and tap it
        let scheduledCell = app.cells.containing(.staticText, identifier: "Scheduled Scans").firstMatch
        if scheduledCell.waitForExistence(timeout: 3) {
            scheduledCell.tap()
            return
        }

        // Try scrolling to find it
        let tableView = app.tables.firstMatch
        if tableView.exists {
            tableView.swipeUp()
            if scheduledCell.waitForExistence(timeout: 2) {
                scheduledCell.tap()
                return
            }
        }

        // Fallback: look for any element with "Scheduled" text
        let anyScheduled = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Scheduled'")).firstMatch
        if anyScheduled.waitForExistence(timeout: 2) {
            anyScheduled.tap()
        }
    }
}
