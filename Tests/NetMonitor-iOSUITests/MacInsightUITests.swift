import XCTest

// The Mac answers "Explain this" for an iPhone without the model (#457). This phone's model is
// unavailable and a scripted Mac advertises insight.v1 (`UITEST_MAC_INSIGHT`); the routing,
// request handling and marker are the app's own. Port Scanner on 127.0.0.1 with the Mail
// preset gives a fixed result with nothing private in the screenshot.

private extension IOSUITestCase {
    func ui(_ id: String) -> XCUIElement {
        app.byID(id).firstMatch
    }

    /// Runs a Mail Ports scan of 127.0.0.1 and taps "Explain this result".
    func scanAndAskForExplanation() {
        app.tabBars.buttons["Tools"].tap()
        // The card sits in a lazy grid, so swipe the Tools screen until it is on screen.
        let card = ui("tools_card_port_scanner")
        let tools = ui("screen_tools")
        requireExists(tools, timeout: 8, message: "Tools screen should open")
        for _ in 0 ..< 6 where !(card.exists && card.isHittable) {
            tools.swipeUp()
        }
        requireExists(card, timeout: 8, message: "Port scanner tool card should exist").tap()
        requireExists(ui("screen_portScannerTool"), timeout: 8, message: "Port scanner should open")

        clearAndTypeText("127.0.0.1", into: app.textFields["portScanner_input_host"])
        // The keyboard would cover the tab bar later on.
        let returnKey = app.keyboards.buttons["Return"].firstMatch
        if returnKey.exists {
            returnKey.tap()
        }
        let picker = app.buttons["portScanner_picker_range"].exists
            ? app.buttons["portScanner_picker_range"]
            : app.byID("portScanner_picker_range")
        picker.tap()
        requireExists(app.buttons["Mail Ports"].firstMatch, timeout: 5, message: "Mail Ports preset should be offered").tap()
        app.buttons["portScanner_button_run"].tap()

        let explain = ui("portScanner_insight_button_explain")
        requireExists(explain, timeout: 60, message: "Explain this result should show once the scan ends, with a Mac that could answer")
        for _ in 0 ..< 4 where !explain.isHittable {
            app.swipeUp()
        }
        explain.tap()
    }

    /// Keeps a screenshot cropped to `parts`, so nothing else on screen goes into the evidence.
    func keepCropped(_ parts: [XCUIElement], named name: String) {
        let image = app.screenshot().image
        let frame = parts.map(\.frame).reduce(parts[0].frame) { $0.union($1) }.insetBy(dx: -12, dy: -12)
        let pixels = CGRect(x: frame.minX * image.scale, y: frame.minY * image.scale,
                            width: frame.width * image.scale, height: frame.height * image.scale)
        guard let cropped = image.cgImage?.cropping(to: pixels) else {
            XCTFail("Could not crop the card from the screenshot")
            return
        }
        let attachment = XCTAttachment(image: UIImage(cgImage: cropped, scale: image.scale, orientation: .up))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The one-time "Use your Mac for on-device AI?" prompt, once it shows.
    func requireMacPrompt() -> XCUIElement {
        let alert = app.alerts["Use your Mac for on-device AI?"]
        requireExists(alert, timeout: 10, message: "The phone should ask before sending anything to the Mac")
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "over your local network")).firstMatch.exists,
                      "The prompt should say requests go to the Mac over the local network")
        return alert
    }

    /// Opens Settings from the dashboard.
    func openSettings() {
        requireExists(app.tabBars.buttons["Dashboard"], message: "Dashboard tab should exist").tap()
        let settingsButton = app.buttons["dashboard_button_settings"]
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        } else {
            requireExists(app.navigationBars.buttons.firstMatch, message: "A navigation bar button should exist for settings").tap()
        }
        requireExists(ui("screen_settings"), timeout: 8, message: "Settings screen should open")
    }
}

@MainActor
final class MacInsightAnswerUITests: IOSUITestCase {
    // Not asked yet: the first "Explain this" asks, and agreeing sends it to the Mac.
    override var additionalLaunchEnvironment: [String: String] { ["UITEST_MAC_INSIGHT": "answer"] }

    func testAgreeingToUseTheMacAnswersExplainThisWithMacMarker() throws {
        scanAndAskForExplanation()

        let alert = requireMacPrompt()
        keepCropped([alert], named: "MacInsight_Prompt")
        alert.buttons["Use My Mac"].firstMatch.tap()

        let text = ui("portScanner_insight_label_text")
        requireExists(text, timeout: 15, message: "The Mac's explanation should appear once the user agrees")
        XCTAssertEqual(
            text.label,
            "None of the mail services on this device answered, so nothing here is accepting mail."
        )
        let marker = ui("portScanner_insight_label_generated")
        requireExists(marker, message: "The generated-text marker should show")
        XCTAssertTrue(marker.label.contains("on-device model on your Mac"), "Marker: \(marker.label)")

        keepCropped([ui("portScanner_insight_list_keyPoints"), text, marker], named: "MacInsight_Answered")
    }
}

@MainActor
final class MacInsightDeclineUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] { ["UITEST_MAC_INSIGHT": "answer"] }

    func testDecliningKeepsTheFallbackAndOffersTheSettingsSwitch() throws {
        scanAndAskForExplanation()

        requireMacPrompt().buttons["Don't Use Mac"].firstMatch.tap()

        // Nothing goes to the Mac: the card goes away and the tool stays as it was without a model.
        XCTAssertTrue(waitForDisappearance(ui("portScanner_insight_button_explain"), timeout: 5), "Explain this should go away")
        XCTAssertFalse(ui("portScanner_insight_label_text").exists, "No generated text should show")
        XCTAssertFalse(app.alerts.firstMatch.exists, "The prompt shouldn't come back")
        XCTAssertTrue(app.buttons["portScanner_button_run"].isEnabled, "The scan can run again")
        keepCropped([ui("screen_portScannerTool")], named: "MacInsight_DeclinedFallback")

        openSettings()
        let toggle = ui("settings_toggle_macInsight")
        for _ in 0 ..< 4 where !toggle.isHittable {
            app.swipeUp()
        }
        requireExists(toggle, message: "Settings should offer the switch after the user answered")
        XCTAssertEqual(toggle.value as? String, "0", "The switch should be off after declining")
        keepCropped([toggle], named: "MacInsight_SettingsSwitchOff")
    }
}

@MainActor
final class MacInsightDisconnectUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_MAC_INSIGHT": "disconnect", "UITEST_MAC_CONSENT": "agreed"]
    }

    func testMacDisconnectMidRequestShowsFallback() throws {
        scanAndAskForExplanation()

        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2), "An answer already given isn't asked again")
        let failed = app.staticTexts["This result couldn't be explained."]
        requireExists(failed, timeout: 15, message: "A Mac that drops mid-request should leave the non-model fallback")
        XCTAssertFalse(ui("portScanner_insight_label_text").exists, "No generated text should show")
        let retry = ui("portScanner_insight_button_retry")
        requireExists(retry, message: "The fallback should offer Try Again")
        // The tool itself still works without the model.
        XCTAssertTrue(app.buttons["portScanner_button_run"].isEnabled, "The scan can run again")

        keepCropped([failed, retry], named: "MacInsight_DisconnectFallback")
    }
}
