import XCTest

final class MacPairingUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Settings, then open Mac pairing sheet
        let settingsButton = app.buttons["dashboard_button_settings"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Settings Connection Section

    func testSettingsScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_settings"].waitForExistence(timeout: 5))
    }

    // MARK: - Mac Pairing Sheet

    func testOpenPairingSheet() throws {
        // The ConnectionSettingsSection has a Connect to Mac button
        let pairButton = app.buttons["settings_button_connectMac"]
        if pairButton.waitForExistence(timeout: 5) {
            pairButton.tap()
            XCTAssertTrue(app.otherElements["screen_macPairing"].waitForExistence(timeout: 5))
        }
    }

    func testPairingScreenElements() throws {
        openPairingSheet()
        if app.otherElements["screen_macPairing"].waitForExistence(timeout: 5) {
            // Cancel button should exist
            XCTAssertTrue(app.buttons["pairing_cancel"].exists)
            // Navigation title
            XCTAssertTrue(app.navigationBars["Connect to Mac"].exists)
        }
    }

    func testSearchingIndicator() throws {
        openPairingSheet()
        if app.otherElements["screen_macPairing"].waitForExistence(timeout: 5) {
            // Either searching indicator, empty state, or discovered macs
            let searching = app.otherElements["pairing_searching"]
            let empty = app.otherElements["pairing_empty"]
            let macList = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pairing_mac_'")).firstMatch
            XCTAssertTrue(searching.waitForExistence(timeout: 5) || empty.exists || macList.exists)
        }
    }

    func testManualConnectionToggle() throws {
        openPairingSheet()
        if app.otherElements["screen_macPairing"].waitForExistence(timeout: 5) {
            let manualToggle = app.buttons["pairing_manual_toggle"]
            if manualToggle.waitForExistence(timeout: 5) {
                manualToggle.tap()
                // Manual entry fields should appear
                XCTAssertTrue(app.textFields["pairing_manual_host"].waitForExistence(timeout: 3))
                XCTAssertTrue(app.textFields["pairing_manual_port"].exists)
                XCTAssertTrue(app.buttons["pairing_manual_connect"].exists ||
                              app.otherElements["pairing_manual_connect"].exists)
            }
        }
    }

    func testManualHostInput() throws {
        openPairingSheet()
        if app.otherElements["screen_macPairing"].waitForExistence(timeout: 5) {
            let manualToggle = app.buttons["pairing_manual_toggle"]
            if manualToggle.waitForExistence(timeout: 5) {
                manualToggle.tap()
                let hostField = app.textFields["pairing_manual_host"]
                if hostField.waitForExistence(timeout: 3) {
                    hostField.tap()
                    hostField.typeText("192.168.1.100")
                    XCTAssertEqual(hostField.value as? String, "192.168.1.100")
                }
            }
        }
    }

    func testCancelDismissesPairingSheet() throws {
        openPairingSheet()
        if app.otherElements["screen_macPairing"].waitForExistence(timeout: 5) {
            app.buttons["pairing_cancel"].tap()
            // Should return to settings
            XCTAssertTrue(app.otherElements["screen_settings"].waitForExistence(timeout: 5))
        }
    }

    // MARK: - Helpers

    private func openPairingSheet() {
        let pairButton = app.buttons["settings_button_connectMac"]
        if pairButton.waitForExistence(timeout: 5) {
            pairButton.tap()
        }
    }
}
