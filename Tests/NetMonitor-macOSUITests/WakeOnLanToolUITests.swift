import XCTest

@MainActor
final class WakeOnLanToolUITests: XCTestCase {
    nonisolated(unsafe) nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools
        let sidebar = app.descendants(matching: .any)["sidebar_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        // Open Wake on LAN tool
        let card = app.otherElements["tools_card_wake_on_lan"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Element Existence

    func testDevicePickerExists() {
        XCTAssertTrue(app.popUpButtons["wol_picker_device"].waitForExistence(timeout: 3))
    }

    func testMACAddressFieldExists() {
        XCTAssertTrue(app.textFields["wol_textfield_mac"].waitForExistence(timeout: 3))
    }

    func testBroadcastFieldExists() {
        XCTAssertTrue(app.textFields["wol_textfield_broadcast"].waitForExistence(timeout: 3))
    }

    func testSendButtonExists() {
        XCTAssertTrue(app.buttons["wol_button_send"].waitForExistence(timeout: 3))
    }

    func testCloseButtonExists() {
        XCTAssertTrue(app.buttons["wol_button_close"].waitForExistence(timeout: 3))
    }

    // MARK: - Interactions

    func testSendButtonDisabledWhenMACEmpty() {
        let sendButton = app.buttons["wol_button_send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 3))
        XCTAssertFalse(sendButton.isEnabled)
    }

    func testCloseButtonDismissesSheet() {
        app.buttons["wol_button_close"].tap()
        XCTAssertTrue(app.otherElements["tools_card_wake_on_lan"].waitForExistence(timeout: 3))
    }

    func testTypeMACAddress() {
        let macField = app.textFields["wol_textfield_mac"]
        XCTAssertTrue(macField.waitForExistence(timeout: 3))
        macField.tap()
        macField.typeText("AA:BB:CC:DD:EE:FF")

        // Send button should become enabled with a valid MAC
        let sendButton = app.buttons["wol_button_send"]
        XCTAssertTrue(sendButton.isEnabled)
    }

    func testBroadcastFieldHasDefaultValue() {
        let broadcastField = app.textFields["wol_textfield_broadcast"]
        XCTAssertTrue(broadcastField.waitForExistence(timeout: 3))
        // Default broadcast address should be 255.255.255.255
        XCTAssertEqual(broadcastField.value as? String, "255.255.255.255")
    }
}
