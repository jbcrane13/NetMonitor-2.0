import XCTest

/// #586 user flow: on an iPhone whose own model can't run, a paired Mac reads what the user types.
/// The first typed rule asks "Let your Mac read what you type and your device details?"; after "Use My Mac" the rule comes
/// back as a draft marked as drafted by the Mac's model, and a typed symptom starts its checks marked
/// as read by the Mac's model. When the Mac leaves, the troubleshooter's field goes and the buttons
/// stay: the path without the model.
///
/// Against the in-app fake Mac (`--fake-mac-pairing`, #590) with `UITEST_FAKE_MAC_MODEL=1`: it
/// advertises `rules.v1` and `symptoms.v1` over the real TLS link and answers with the stand-in
/// model's unchecked readings; the phone's own model is unavailable. The phone's checks, routing
/// and consent are real. A printer and a NAS are seeded on the UI-test network. Screenshots are
/// cropped to the elements; every device is a fixture.
@MainActor
final class MacModelUITests: PresenceUITestCase {
    private static let code = "14D2P-F2DBS-QQG28-T5CY4-TQKFF-K"

    override var additionalLaunchArguments: [String] { ["--fake-mac-pairing"] }
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_PAIRING_CODE": Self.code, "UITEST_FAKE_DEVICES": "1", "UITEST_SEED_RULE_DEVICES": "1", "UITEST_FAKE_MAC_MODEL": "1"]
    }

    func testTheMacReadsATypedRuleAndSymptomThenTheButtonsStayWhenItLeaves() {
        pairWithFakeMac()

        // A typed rule: asked once, then drafted by the Mac's model.
        app.tabBars.buttons["Dashboard"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        describeRule("scan web ports on the printer")
        let alert = app.alerts["Let your Mac read what you type and your device details?"]
        requireExists(alert, timeout: 5, message: "The first typed rule should ask before anything is sent")
        keepCroppedEvidence(alert, named: "586-01-consent")
        alert.buttons["Use My Mac"].firstMatch.tap()

        let summary = ui("settings_label_ruleDraftSummary")
        requireExists(summary, timeout: 15, message: "The Mac's reading should come back as a draft")
        XCTAssertEqual(summary.label, "Scan web ports on uitest-printer (192.168.77.20)")
        let marker = ui("settings_label_ruleDraftMarker")
        XCTAssertTrue(marker.label.contains("on-device model on your Mac"), "Marked as the Mac's: \(marker.label)")
        keepCroppedEvidence(marker, named: "586-02-rule-marker")
        keepCroppedEvidence(summary, named: "586-03-rule-draft")
        ui("settings_button_cancelRuleDraft").tap()
        // Leave Settings, which also puts the keyboard away: it covers the tab bar.
        app.navigationBars["Settings"].buttons.firstMatch.tap()

        // A typed symptom: no second question, its checks start, marked as read by the Mac.
        openTroubleshooter()
        let field = ui("troubleshoot_field_symptom")
        requireExists(field, timeout: 8, message: "The symptom field should show while the Mac reads symptoms")
        field.tap()
        field.typeText("the wifi is weak in the bedroom")
        requireExists(ui("troubleshoot_button_start"), message: "Start should be offered").tap()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 1), "Consent was already given")
        let source = ui("troubleshoot_label_symptomSource")
        requireExists(source, timeout: 15, message: "The checks should start, marked as read by the Mac")
        XCTAssertEqual(source.label, "Read by the on-device model on your Mac from your words")
        XCTAssertTrue(app.staticTexts["Where: bedroom"].exists, "The room the user typed")
        XCTAssertTrue(app.staticTexts["Wi-Fi is weak"].exists, "The weak Wi-Fi checks")
        // Clear of the tab bar: the marker and the room the user typed.
        let screen = ui("screen_troubleshootTool")
        for _ in 0 ..< 3 where source.frame.maxY > app.tabBars.firstMatch.frame.minY - 20 {
            screen.swipeUp(velocity: .slow)
        }
        keepCroppedEvidence(source, named: "586-04-symptom-marker")
        keepCroppedEvidence(app.staticTexts["Where: bedroom"], named: "586-04b-symptom-room")
        let cancel = ui("troubleshoot_button_cancel")
        if cancel.exists {
            cancel.tap()
        }

        // The Mac leaves: the field goes, the buttons stay.
        openSettings()
        let leaves = app.buttons["settings_button_uitestFakeMacLeaves"]
        scrollToElement(leaves)
        requireExists(leaves, timeout: 5, message: "The UI-test control for the fake Mac leaving").tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForNonExistence(timeout: 30), "The link drops")
        openTroubleshooter()
        XCTAssertFalse(ui("troubleshoot_field_symptom").exists, "No capable Mac: no field")
        let button = ui("troubleshoot_button_kind_weakWiFi")
        requireExists(button, timeout: 5, message: "The buttons stay")
        keepCroppedEvidence(button, named: "586-05-fallback-buttons")
    }

    // MARK: - Helpers

    private func openTroubleshooter() {
        app.tabBars.buttons["Tools"].tap()
        app.tabBars.buttons["Tools"].tap()
        let tools = ui("screen_tools")
        requireExists(tools, timeout: 8, message: "Tools screen should open")
        let card = ui("tools_card_troubleshoot")
        for _ in 0 ..< 6 where !(card.exists && card.isHittable) {
            tools.swipeUp()
        }
        requireExists(card, timeout: 8, message: "Troubleshoot card should be in the Diagnostics tools").tap()
        requireExists(ui("screen_troubleshootTool"), timeout: 8, message: "The troubleshooter should open")
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
