import XCTest

/// User flow for #449: opening a device the app couldn't identify shows what the on-device
/// model suggests, marked as a suggestion, and the user keeps it with Accept or drops it
/// with Dismiss.
///
/// `UITEST_FAKE_DEVICES=1` lists fake devices, and `UITEST_FAKE_SUGGESTION=1` gives them no
/// MAC-prefix maker and makes device detail ask a fixed-suggestion service (a Brother
/// HL-L2350DW printer), since the simulator has no on-device model.
@MainActor
final class DeviceIdentitySuggestionUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_FAKE_SUGGESTION": "1"]
    }

    func testAcceptKeepsTheSuggestedMakerModelAndType() throws {
        openFirstDevice()

        let badge = element("deviceDetail_badge_suggested")
        requireExists(badge, timeout: 10, message: "Device detail should mark the model's suggestion")
        XCTAssertTrue(app.staticTexts["Brother"].exists, "The suggested maker should be shown")
        XCTAssertTrue(app.staticTexts["HL-L2350DW"].exists, "The suggested model should be shown")
        XCTAssertTrue(app.staticTexts["Printer"].exists, "The suggested type should be shown")
        captureScreenshot(named: "DeviceDetail_IdentitySuggestion_Shown")

        let accept = element("deviceDetail_button_acceptSuggestion")
        scrollToElement(accept)
        accept.tap()

        XCTAssertTrue(waitForDisappearance(badge, timeout: 5), "Accepting should remove the suggestion mark")
        XCTAssertTrue(app.staticTexts["Brother"].exists, "The accepted maker should stay")
        XCTAssertTrue(app.staticTexts["HL-L2350DW"].exists, "The accepted model should stay")
        XCTAssertTrue(app.staticTexts["Printer"].exists, "The accepted type should become the device's type")
        XCTAssertFalse(element("deviceDetail_button_acceptSuggestion").exists)
        captureScreenshot(named: "DeviceDetail_IdentitySuggestion_Accepted")
    }

    func testDismissHidesTheSuggestion() throws {
        openFirstDevice()

        let badge = element("deviceDetail_badge_suggested")
        requireExists(badge, timeout: 10, message: "Device detail should mark the model's suggestion")

        let dismiss = element("deviceDetail_button_dismissSuggestion")
        scrollToElement(dismiss)
        dismiss.tap()

        XCTAssertTrue(waitForDisappearance(badge, timeout: 5), "Dismissing should remove the suggestion mark")
        XCTAssertFalse(app.staticTexts["Brother"].exists, "The dismissed maker should be gone")
        XCTAssertFalse(app.staticTexts["HL-L2350DW"].exists, "The dismissed model should be gone")
        XCTAssertFalse(app.staticTexts["Printer"].exists, "The dismissed type should be gone")
        XCTAssertTrue(app.staticTexts["Unknown"].exists, "The device's type should still be unknown")
        captureScreenshot(named: "DeviceDetail_IdentitySuggestion_Dismissed")
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openFirstDevice() {
        let devicesCard = element("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, timeout: 10, message: "Local devices card should exist on dashboard")
        devicesCard.tap()

        let firstDeviceRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'deviceList_row_device_'")
        ).firstMatch
        requireExists(firstDeviceRow, timeout: 8, message: "Fake device feed should list a device")
        firstDeviceRow.tap()

        requireExists(element("screen_deviceDetail"), timeout: 5, message: "Device detail should open")
    }
}
