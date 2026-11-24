import XCTest

// The Mac answers "Explain this" for an iPhone without the model (#457). This phone's model is
// unavailable and a scripted Mac advertises insight.v1 (`UITEST_MAC_INSIGHT`); the routing,
// request handling and marker are the app's own. Port Scanner on 127.0.0.1 with the Mail
// preset gives a fixed result with nothing private in the screenshot.

private extension IOSUITestCase {
    func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
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
        let picker = app.buttons["portScanner_picker_range"].exists
            ? app.buttons["portScanner_picker_range"]
            : app.otherElements["portScanner_picker_range"]
        picker.tap()
        requireExists(app.buttons["Mail Ports"].firstMatch, timeout: 5, message: "Mail Ports preset should be offered").tap()
        app.buttons["portScanner_button_run"].tap()

        let explain = ui("portScanner_insight_button_explain")
        requireExists(explain, timeout: 60, message: "Explain this result should show once the scan ends, answered by the Mac")
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
}

@MainActor
final class MacInsightAnswerUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] { ["UITEST_MAC_INSIGHT": "answer"] }

    func testMacAnswersExplainThisWithMacMarker() throws {
        scanAndAskForExplanation()

        let text = ui("portScanner_insight_label_text")
        requireExists(text, timeout: 15, message: "The Mac's explanation should appear")
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
final class MacInsightDisconnectUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] { ["UITEST_MAC_INSIGHT": "disconnect"] }

    func testMacDisconnectMidRequestShowsFallback() throws {
        scanAndAskForExplanation()

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
