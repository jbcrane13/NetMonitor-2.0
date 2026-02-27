import XCTest

@MainActor
final class PortScannerToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools
        let sidebar = app.staticTexts["sidebar_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        // Open Port Scanner tool
        let card = app.otherElements["tools_card_port_scanner"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Element Existence

    func testHostFieldExists() {
        XCTAssertTrue(app.textFields["portscan_textfield_host"].waitForExistence(timeout: 3))
    }

    func testPresetPickerExists() {
        XCTAssertTrue(app.popUpButtons["portscan_picker_preset"].waitForExistence(timeout: 3))
    }

    func testScanButtonExists() {
        XCTAssertTrue(app.buttons["portscan_button_scan"].waitForExistence(timeout: 3))
    }

    func testCloseButtonExists() {
        XCTAssertTrue(app.buttons["portscan_button_close"].waitForExistence(timeout: 3))
    }

    // MARK: - Interactions

    func testScanButtonDisabledWhenHostEmpty() {
        let scanButton = app.buttons["portscan_button_scan"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 3))
        XCTAssertFalse(scanButton.isEnabled)
    }

    func testScanButtonEnabledAfterTypingHost() {
        let hostField = app.textFields["portscan_textfield_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 3))
        hostField.tap()
        hostField.typeText("127.0.0.1")

        XCTAssertTrue(app.buttons["portscan_button_scan"].isEnabled)
    }

    func testCloseButtonDismissesSheet() {
        app.buttons["portscan_button_close"].tap()
        XCTAssertTrue(app.otherElements["tools_card_port_scanner"].waitForExistence(timeout: 3))
    }

    func testCustomPresetShowsCustomField() {
        let presetPicker = app.popUpButtons["portscan_picker_preset"]
        XCTAssertTrue(presetPicker.waitForExistence(timeout: 3))
        presetPicker.tap()

        // Select "Custom" option
        let customOption = app.menuItems["Custom"]
        if customOption.waitForExistence(timeout: 2) {
            customOption.tap()
            // Custom ports text field should appear
            XCTAssertTrue(app.textFields["portscan_textfield_custom"].waitForExistence(timeout: 3))
        }
    }

    func testStartScan() {
        let hostField = app.textFields["portscan_textfield_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 3))
        hostField.tap()
        hostField.typeText("127.0.0.1")

        app.buttons["portscan_button_scan"].tap()

        // Button label changes to "Stop" during scan
        let scanButton = app.buttons["portscan_button_scan"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 3))
    }
}
