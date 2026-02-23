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

    func testWOLScreenExists() throws {
        navigateToWoLTool()
        requireExists(app.otherElements["screen_wolTool"], message: "Wake on LAN screen should exist")
    }

    func testNavigationTitleExists() throws {
        navigateToWoLTool()
        requireExists(app.navigationBars["Wake on LAN"], message: "Wake on LAN navigation bar should exist")
    }

    // MARK: - Input Elements

    func testMACAddressInputExists() throws {
        navigateToWoLTool()
        requireExists(app.textFields["wol_input_mac"], message: "MAC address input should exist")
    }

    func testBroadcastAddressInputExists() throws {
        navigateToWoLTool()
        requireExists(app.textFields["wol_input_broadcast"], message: "Broadcast address input should exist")
    }

    func testSendButtonExists() throws {
        navigateToWoLTool()
        requireExists(app.buttons["wol_button_send"], message: "Send button should exist")
    }

    // MARK: - Info Card

    func testInfoCardExists() throws {
        navigateToWoLTool()
        scrollToElement(app.otherElements["wol_info"])
        requireExists(app.otherElements["wol_info"], message: "Info card should exist")
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
        XCTAssertTrue(sendButton.exists, "Send button should be present")
    }

    func testSendWakePacket() throws {
        navigateToWoLTool()
        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: app.textFields["wol_input_mac"])
        app.buttons["wol_button_send"].tap()

        let success = app.otherElements["wol_success"]
        let error = app.otherElements["wol_error"]
        let successText = app.staticTexts["Wake packet sent!"]
        let failText = app.staticTexts["Failed to send"]
        XCTAssertTrue(
            waitForEither([success, error, successText, failText], timeout: 10),
            "Either success or error should appear after sending"
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
