import XCTest

/// #586 PR 2 user flow: on an iPhone whose own model can't run, a paired Mac suggests what a device
/// is. Device detail marks the suggestion "Suggested by your Mac", and Accept keeps the maker,
/// model and type. When the Mac leaves, another device gets no suggestion and stays as it was:
/// the path without the model.
///
/// Against the in-app fake Mac (`--fake-mac-pairing`, #590) with `UITEST_FAKE_MAC_MODEL=1`: it
/// advertises `identity.v1` over the real TLS link and answers every device with the stand-in
/// model's unchecked suggestion (a Brother HL-L2350DW printer). The phone's own model is off, and
/// the user already agreed to "Let your Mac read what you type?" (`UITEST_MAC_READING_CONSENT`),
/// since suggestions never ask. `UITEST_FAKE_DEVICES=1` lists fixture devices with no MAC-prefix
/// maker. Screenshots are cropped to elements; every device is a fixture.
@MainActor
final class MacIdentityUITests: PresenceUITestCase {
    private static let code = "14D2P-F2DBS-QQG28-T5CY4-TQKFF-K"

    override var additionalLaunchArguments: [String] { ["--fake-mac-pairing"] }
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_PAIRING_CODE": Self.code, "UITEST_FAKE_DEVICES": "1", "UITEST_FAKE_MAC_MODEL": "1", "UITEST_MAC_READING_CONSENT": "agreed"]
    }

    func testTheMacSuggestsWhatADeviceIsAndAcceptKeepsItThenNothingWhenItLeaves() {
        pairWithFakeMac()

        openDevice(at: 0)
        let badge = ui("deviceDetail_badge_suggested")
        requireExists(badge, timeout: 15, message: "Device detail should show the Mac's suggestion")
        XCTAssertEqual(badge.label, "Suggested by the on-device model on your Mac")
        XCTAssertTrue(app.staticTexts["Brother"].exists, "The suggested maker should be shown")
        XCTAssertTrue(app.staticTexts["HL-L2350DW"].exists, "The suggested model should be shown")
        keepCroppedEvidence(badge, named: "586-pr2-01-suggested-by-your-mac")
        keepRegion(from: ui("deviceDetail_row_hostname"), to: badge, named: "586-pr2-02-suggested-identity")

        let accept = ui("deviceDetail_button_acceptSuggestion")
        scrollToElement(accept)
        accept.tap()
        XCTAssertTrue(waitForDisappearance(badge, timeout: 5), "Accepting removes the suggestion mark")
        XCTAssertTrue(app.staticTexts["Brother"].exists, "The accepted maker stays")
        XCTAssertTrue(app.staticTexts["Printer"].exists, "The accepted type becomes the device's type")
        keepRegion(from: ui("deviceDetail_row_hostname"), to: ui("deviceDetail_row_deviceType"), named: "586-pr2-03-accepted-identity")

        // The Mac leaves: another device gets no suggestion.
        openSettings()
        let leaves = app.buttons["settings_button_uitestFakeMacLeaves"]
        scrollToElement(leaves)
        requireExists(leaves, timeout: 5, message: "The UI-test control for the fake Mac leaving").tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForNonExistence(timeout: 30), "The link drops")
        openDevice(at: 1)
        XCTAssertFalse(ui("deviceDetail_badge_suggested").waitForExistence(timeout: 8), "No capable Mac: no suggestion")
        XCTAssertFalse(app.staticTexts["Brother"].exists, "Nothing suggested for this device")
        let type = ui("deviceDetail_row_deviceType")
        requireExists(type, timeout: 5, message: "The type row stays")
        XCTAssertTrue(app.staticTexts["Unknown"].exists, "Its type is still unknown")
        keepRegion(from: ui("deviceDetail_row_hostname"), to: type, named: "586-pr2-04-no-mac-no-suggestion")
    }

    // MARK: - Helpers

    /// A screenshot of the strip from `top` to `bottom`, full width: the identity rows only.
    private func keepRegion(from top: XCUIElement, to bottom: XCUIElement, named name: String) {
        let image = app.screenshot().image
        let minY = min(top.frame.minY, bottom.frame.minY) - 8
        let maxY = max(top.frame.maxY, bottom.frame.maxY) + 8
        let frame = CGRect(x: 0, y: minY, width: image.size.width, height: maxY - minY)
        let pixels = CGRect(x: 0, y: frame.minY * image.scale, width: frame.width * image.scale, height: frame.height * image.scale)
        guard let cropped = image.cgImage?.cropping(to: pixels) else {
            XCTFail("Could not crop \(name)")
            return
        }
        let attachment = XCTAttachment(image: UIImage(cgImage: cropped, scale: image.scale, orientation: .up))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openDevice(at index: Int) {
        app.tabBars.buttons["Dashboard"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, timeout: 10, message: "Local devices card should exist on dashboard")
        devicesCard.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'deviceList_row_device_'"))
            .element(boundBy: index)
        requireExists(row, timeout: 8, message: "The fake device feed should list device \(index)")
        row.tap()
        requireExists(ui("screen_deviceDetail"), timeout: 5, message: "Device detail should open")
    }

    private func openSettings() {
        requireExists(app.tabBars.buttons["Dashboard"], message: "Dashboard tab should exist").tap()
        app.tabBars.buttons["Dashboard"].tap()
        let settingsButton = app.buttons["dashboard_button_settings"]
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        } else {
            requireExists(app.navigationBars.buttons.firstMatch, message: "A navigation bar button should exist for settings").tap()
        }
        requireExists(app.byID("screen_settings"), timeout: 8, message: "Settings screen should open")
    }

    private func pairWithFakeMac() {
        openSettings()
        let connect = app.buttons["settings_button_connectMac"]
        scrollToElement(connect)
        requireExists(connect, message: "Connect to Mac").tap()
        requireExists(app.buttons["pairing_row_Test Mac"], timeout: 8, message: "The fake Mac should be listed").tap()
        let field = requireExists(app.textFields["pairMac_textfield_code"], timeout: 5, message: "The code field should show")
        field.tap()
        field.typeText(Self.code + "\n")
        requireExists(app.buttons["pairMac_button_pairWithCode"], message: "Pair button").tap()
        requireExists(app.buttons["pairMac_button_codesMatch"], timeout: 8, message: "They Match").tap()
        requireExists(app.staticTexts["pairMac_label_paired"], timeout: 10, message: "The Mac confirms and the phone pins it")
        app.buttons["pairMac_button_done"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 10), "The paired link comes up")
        app.swipeDown(velocity: .fast)
        if app.byID("screen_macPairing").exists {
            app.navigationBars.firstMatch.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(waitForDisappearance(app.byID("screen_macPairing"), timeout: 5), "The pairing sheet closes")
    }
}
