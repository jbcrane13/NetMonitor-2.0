import XCTest

@MainActor
final class WakeOnLANToolUITests: IOSUITestCase {

    private func navigateToWoLTool() {
        app.tabBars.buttons["Tools"].tap()
        let wolCard = app.otherElements["tools_card_wake_on_lan"]
        scrollToElement(wolCard)
        requireExists(wolCard, timeout: 8, message: "Wake on LAN tool card should exist")
        wolCard.tap()
        requireExists(app.otherElements["screen_wolTool"], timeout: 8, message: "Wake on LAN tool screen should appear")
    }

    // MARK: - Screen Existence

    func testWOLScreenExistsAndShowsControls() throws {
        navigateToWoLTool()
        let screen = app.otherElements["screen_wolTool"]
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "Wake on LAN screen should exist")
        // FUNCTIONAL: screen should show MAC input and send button
        XCTAssertTrue(
            app.textFields["wol_input_mac"].waitForExistence(timeout: 3),
            "WoL screen should show MAC address input field"
        )
        XCTAssertTrue(
            app.buttons["wol_button_send"].waitForExistence(timeout: 3),
            "WoL screen should show send button"
        )
    }

    func testNavigationTitleExists() throws {
        navigateToWoLTool()
        requireExists(app.navigationBars["Wake on LAN"], message: "Wake on LAN navigation bar should exist")
    }

    // MARK: - Input Elements

    func testMACAddressInputAcceptsText() throws {
        navigateToWoLTool()
        let macField = app.textFields["wol_input_mac"]
        XCTAssertTrue(macField.waitForExistence(timeout: 5), "MAC address input should exist")
        // FUNCTIONAL: field accepts and reflects typed text
        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: macField)
        XCTAssertEqual(macField.value as? String, "AA:BB:CC:DD:EE:FF", "MAC field should contain typed address")
    }

    func testBroadcastAddressInputExistsWithDefault() throws {
        navigateToWoLTool()
        let broadcastField = app.textFields["wol_input_broadcast"]
        XCTAssertTrue(broadcastField.waitForExistence(timeout: 5), "Broadcast address input should exist")
        // FUNCTIONAL: broadcast field should have a default value
        let value = broadcastField.value as? String ?? ""
        XCTAssertFalse(value.isEmpty, "Broadcast field should have a default value")
    }

    func testSendButtonDisabledWithoutValidMAC() throws {
        navigateToWoLTool()
        let sendButton = requireExists(app.buttons["wol_button_send"], message: "Send button should exist")
        // FUNCTIONAL: send should be disabled without MAC, enabled with valid MAC
        XCTAssertFalse(sendButton.isEnabled, "Send button should be disabled without MAC address")
        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: app.textFields["wol_input_mac"])
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled with valid MAC address")
    }

    // MARK: - Info Card

    func testInfoCardExistsAndHasContent() throws {
        navigateToWoLTool()
        scrollToElement(app.otherElements["wol_label_info"])
        let infoLabel = app.otherElements["wol_label_info"]
        XCTAssertTrue(infoLabel.waitForExistence(timeout: 5), "Info card should exist")
        // FUNCTIONAL: info card should contain descriptive text
        XCTAssertTrue(
            infoLabel.staticTexts.count > 0,
            "Info card should contain descriptive text about Wake on LAN"
        )
    }

    // MARK: - Input Interaction

    func testTypeMACAddress() throws {
        navigateToWoLTool()
        let macField = app.textFields["wol_input_mac"]
        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: macField)
        XCTAssertEqual(macField.value as? String, "AA:BB:CC:DD:EE:FF")
    }

    func testTypeBroadcastAddress() throws {
        navigateToWoLTool()
        let broadcastField = app.textFields["wol_input_broadcast"]
        requireExists(broadcastField, message: "Broadcast field should exist")
        broadcastField.tap()
        if let currentValue = broadcastField.value as? String, !currentValue.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            broadcastField.typeText(deleteString)
        }
        broadcastField.typeText("192.168.1.255")
    }

    // MARK: - Send Wake Packet

    func testSendButtonDisabledWithoutMAC() throws {
        navigateToWoLTool()
        let sendButton = requireExists(app.buttons["wol_button_send"], message: "Send button should exist")
        XCTAssertFalse(sendButton.isEnabled, "Send button should be disabled when MAC field is empty")
    }

    func testSendWakePacketProducesOutcome() throws {
        navigateToWoLTool()
        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: app.textFields["wol_input_mac"])
        app.buttons["wol_button_send"].tap()

        let success = app.otherElements["wol_label_success"]
        let error = app.otherElements["wol_label_error"]
        let successText = app.staticTexts["Wake packet sent!"]
        let failText = app.staticTexts["Failed to send"]
        XCTAssertTrue(
            waitForEither([success, error, successText, failText], timeout: 10),
            "Either success or error should appear after sending"
        )
        // FUNCTIONAL: verify a definitive outcome was reached
        XCTAssertTrue(
            success.exists || error.exists || successText.exists || failText.exists,
            "Wake on LAN should reach a conclusive success or failure state after sending"
        )
    }

    // MARK: - Validation

    func testInvalidMACShowsValidationError() throws {
        navigateToWoLTool()
        clearAndTypeText("1234", into: app.textFields["wol_input_mac"])
        requireExists(
            app.staticTexts["Invalid MAC address format"],
            message: "Invalid MAC helper text should appear for malformed address"
        )
        // FUNCTIONAL: send button should remain disabled for invalid MAC
        let sendButton = app.buttons["wol_button_send"]
        XCTAssertFalse(sendButton.isEnabled, "Send button should be disabled for invalid MAC format")
    }

    func testValidMACClearsValidationError() throws {
        navigateToWoLTool()
        clearAndTypeText("1234", into: app.textFields["wol_input_mac"])
        requireExists(
            app.staticTexts["Invalid MAC address format"],
            message: "Invalid MAC helper text should appear first"
        )

        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: app.textFields["wol_input_mac"])
        requireExists(
            app.staticTexts["Valid MAC address"],
            message: "Valid MAC helper text should appear after entering a well-formed address"
        )
        // FUNCTIONAL: send button should now be enabled
        let sendButton = app.buttons["wol_button_send"]
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled for valid MAC address")
    }

    func testBroadcastFieldHasDefaultValue() throws {
        navigateToWoLTool()
        let broadcastField = requireExists(
            app.textFields["wol_input_broadcast"],
            message: "Broadcast field should exist"
        )
        let value = broadcastField.value as? String ?? ""
        XCTAssertEqual(value, "255.255.255.255", "Broadcast field should default to 255.255.255.255")
    }
}
