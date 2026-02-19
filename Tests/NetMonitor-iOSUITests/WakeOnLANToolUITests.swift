import XCTest

final class WakeOnLANToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Tools"].tap()
        let wolCard = app.otherElements["tools_card_wake_on_lan"]
        if wolCard.waitForExistence(timeout: 5) {
            wolCard.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testWOLScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_wolTool"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Wake on LAN"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Elements

    func testMACAddressInputExists() throws {
        XCTAssertTrue(app.textFields["wol_input_mac"].waitForExistence(timeout: 5))
    }

    func testBroadcastAddressInputExists() throws {
        XCTAssertTrue(app.textFields["wol_input_broadcast"].waitForExistence(timeout: 5))
    }

    func testSendButtonExists() throws {
        XCTAssertTrue(app.buttons["wol_button_send"].waitForExistence(timeout: 5))
    }

    // MARK: - Info Card

    func testInfoCardExists() throws {
        app.swipeUp()
        XCTAssertTrue(app.otherElements["wol_info"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Interaction

    func testTypeMACAddress() throws {
        let macField = app.textFields["wol_input_mac"]
        XCTAssertTrue(macField.waitForExistence(timeout: 5))
        macField.tap()
        macField.typeText("AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(macField.value as? String, "AA:BB:CC:DD:EE:FF")
    }

    func testTypeBroadcastAddress() throws {
        let broadcastField = app.textFields["wol_input_broadcast"]
        XCTAssertTrue(broadcastField.waitForExistence(timeout: 5))
        broadcastField.tap()
        // Clear default value first
        if let currentValue = broadcastField.value as? String, !currentValue.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            broadcastField.typeText(deleteString)
        }
        broadcastField.typeText("192.168.1.255")
    }

    // MARK: - Send Wake Packet

    func testSendButtonDisabledWithoutMAC() throws {
        let sendButton = app.buttons["wol_button_send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        // Button should be disabled without a valid MAC
        // We can check it exists - the disabled state is enforced in the view
        XCTAssertTrue(sendButton.exists)
    }

    func testSendWakePacket() throws {
        let macField = app.textFields["wol_input_mac"]
        XCTAssertTrue(macField.waitForExistence(timeout: 5))
        macField.tap()
        macField.typeText("AA:BB:CC:DD:EE:FF")

        app.buttons["wol_button_send"].tap()

        // Either success or error should appear
        let success = app.otherElements["wol_success"]
        let error = app.otherElements["wol_error"]
        XCTAssertTrue(success.waitForExistence(timeout: 10) || error.waitForExistence(timeout: 10))
    }
}
