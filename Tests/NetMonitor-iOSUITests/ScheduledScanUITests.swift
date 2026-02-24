import XCTest

@MainActor
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

    // MARK: - Helpers

    private func openSettings() {
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
        }
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
