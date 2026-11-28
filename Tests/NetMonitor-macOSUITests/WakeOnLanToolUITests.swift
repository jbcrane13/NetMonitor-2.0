import XCTest

@MainActor
final class WakeOnLanToolUITests: MacOSUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openTool(cardID: "tools_card_wake_on_lan", sheetElement: "wol_button_close")
    }

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
        closeTool(closeButtonID: "wol_button_close", cardID: "tools_card_wake_on_lan")
    }

    func testTypeMACAddress() {
        let macField = app.textFields["wol_textfield_mac"]
        XCTAssertTrue(macField.waitForExistence(timeout: 3))
        macField.click()
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

    // MARK: - Outcome: Send Produces Result Label

    /// Tapping Send with a valid MAC should render either the success label
    /// (`wol_label_result`) or the error label (`wol_label_error`). Either
    /// proves the send action fed a result back into the view.
    func testSendPacketProducesResultLabel() {
        let macField = app.textFields["wol_textfield_mac"]
        XCTAssertTrue(macField.waitForExistence(timeout: 3))
        macField.click()
        macField.typeText("AA:BB:CC:DD:EE:FF")

        app.buttons["wol_button_send"].click()

        let success = ui("wol_label_result").firstMatch
        let failure = ui("wol_label_error").firstMatch

        XCTAssertTrue(
            waitForEither([success, failure], timeout: 10),
            "Wake on LAN should render a result or error label after sending packet"
        )
    }
}
