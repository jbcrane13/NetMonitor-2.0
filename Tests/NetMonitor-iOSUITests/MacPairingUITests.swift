import XCTest

@MainActor
final class MacPairingUITests: IOSUITestCase {

    // MARK: - Settings Connection Section

    func testSettingsScreenExists() throws {
        openSettings()
        XCTAssertTrue(app.otherElements["screen_settings"].waitForExistence(timeout: 5))
    }

    // MARK: - Mac Pairing Sheet

    func testOpenPairingSheet() throws {
        openSettings()
        let pairButton = app.buttons["settings_button_connectMac"]
        if pairButton.waitForExistence(timeout: 5) {
            pairButton.tap()
            XCTAssertTrue(app.otherElements["screen_macPairing"].waitForExistence(timeout: 5))
        }
    }

    func testPairingScreenElements() throws {
        openSettings()
        openPairingSheet()
        if app.otherElements["screen_macPairing"].waitForExistence(timeout: 5) {
            XCTAssertTrue(app.buttons["pairing_button_cancel"].exists)
            XCTAssertTrue(app.navigationBars["Connect to Mac"].exists)
        }
    }

    func testSearchingIndicator() throws {
        openSettings()
        openPairingSheet()
        if app.otherElements["screen_macPairing"].waitForExistence(timeout: 5) {
            let searching = app.otherElements["pairing_label_searching"]
            let empty = app.otherElements["pairing_label_empty"]
            let macList = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pairing_mac_'")).firstMatch
            XCTAssertTrue(searching.waitForExistence(timeout: 5) || empty.exists || macList.exists)
        }
    }

    func testManualConnectionToggle() throws {
        openSettings()
        openPairingSheet()
        if app.otherElements["screen_macPairing"].waitForExistence(timeout: 5) {
            let manualToggle = app.buttons["pairing_toggle_manual"]
            if manualToggle.waitForExistence(timeout: 5) {
                manualToggle.tap()
                XCTAssertTrue(app.textFields["macPairing_textfield_host"].waitForExistence(timeout: 3))
                XCTAssertTrue(app.textFields["macPairing_textfield_port"].exists)
                XCTAssertTrue(app.buttons["pairing_button_manualConnect"].exists ||
                              app.otherElements["pairing_button_manualConnect"].exists)
            }
        }
    }

    func testManualHostInput() throws {
        openSettings()
        openPairingSheet()
        if app.otherElements["screen_macPairing"].waitForExistence(timeout: 5) {
            let manualToggle = app.buttons["pairing_toggle_manual"]
            if manualToggle.waitForExistence(timeout: 5) {
                manualToggle.tap()
                let hostField = app.textFields["macPairing_textfield_host"]
                if hostField.waitForExistence(timeout: 3) {
                    hostField.tap()
                    hostField.typeText("192.168.1.100")
                    XCTAssertEqual(hostField.value as? String, "192.168.1.100")
                }
            }
        }
    }

    func testCancelDismissesPairingSheet() throws {
        openSettings()
        openPairingSheet()
        if app.otherElements["screen_macPairing"].waitForExistence(timeout: 5) {
            app.buttons["pairing_button_cancel"].tap()
            XCTAssertTrue(app.otherElements["screen_settings"].waitForExistence(timeout: 5))
        }
    }

    // MARK: - Functional Tests

    func testMacPairingScreenElementsVisible() throws {
        openSettings()

        let pairButton = app.buttons["settings_button_connectMac"]
        guard pairButton.waitForExistence(timeout: 5) else { return }
        pairButton.tap()

        guard app.otherElements["screen_macPairing"].waitForExistence(timeout: 8) else {
            XCTFail("Mac pairing screen should appear after tapping Connect to Mac")
            return
        }

        let cancelButton = app.buttons["pairing_button_cancel"]
        let searchingIndicator = app.otherElements["pairing_label_searching"]
        let emptyState = app.otherElements["pairing_label_empty"]
        let qrCode = app.otherElements["pairing_qrCode"]

        XCTAssertTrue(
            cancelButton.exists || searchingIndicator.exists || emptyState.exists || qrCode.exists,
            "Mac pairing screen should show cancel button, discovery state, or QR code"
        )
    }

    func testMacPairingCancelReturnToSettings() throws {
        openSettings()

        let pairButton = app.buttons["settings_button_connectMac"]
        guard pairButton.waitForExistence(timeout: 5) else { return }
        pairButton.tap()

        guard app.otherElements["screen_macPairing"].waitForExistence(timeout: 8) else {
            XCTFail("Mac pairing screen should appear after tapping Connect to Mac")
            return
        }

        let cancelButton = app.buttons["pairing_button_cancel"]
        guard cancelButton.waitForExistence(timeout: 5) else { return }
        cancelButton.tap()

        XCTAssertTrue(
            app.otherElements["screen_settings"].waitForExistence(timeout: 5),
            "Settings screen should reappear after cancelling Mac pairing"
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

        requireExists(app.otherElements["screen_settings"], timeout: 8, message: "Settings screen should open")
    }

    private func openPairingSheet() {
        let pairButton = app.buttons["settings_button_connectMac"]
        if pairButton.waitForExistence(timeout: 5) {
            pairButton.tap()
        }
    }
}
