import XCTest

// MARK: - Shared steps

private extension IOSUITestCase {
    func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Opens Tools → Ask, in Monitoring.
    func openAsk() {
        app.tabBars.buttons["Tools"].tap()
        let tools = ui("screen_tools")
        requireExists(tools, timeout: 8, message: "Tools screen should open")
        let card = ui("tools_card_ask")
        for _ in 0 ..< 8 where !(card.exists && card.isHittable) {
            tools.swipeUp()
        }
        requireExists(card, timeout: 8, message: "The Ask card should be in the Monitoring tools").tap()
        requireExists(ui("ask_field_question"), timeout: 8, message: "The question field should show")
    }

    /// Types `question` and taps Ask.
    func ask(_ question: String) {
        let field = ui("ask_field_question")
        field.tap()
        field.typeText(question)
        requireExists(ui("ask_button_ask"), message: "Ask should be offered").tap()
    }

    /// Waits until the answer's text is `text`.
    func waitForAnswer(_ text: String) -> XCUIElement {
        let answer = ui("ask_label_answer")
        requireExists(answer, timeout: 10, message: "An answer should show")
        let matches = expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: answer)
        wait(for: [matches], timeout: 10)
        return answer
    }

    /// Keeps a screenshot cropped to `parts`, so no other screen content goes into the evidence.
    func keep(_ parts: [XCUIElement], named name: String) {
        let image = app.screenshot().image
        let frame = parts.map(\.frame).reduce(parts[0].frame) { $0.union($1) }.insetBy(dx: -12, dy: -12)
        let visible = frame.intersection(CGRect(origin: .zero, size: image.size))
        let pixels = CGRect(x: visible.minX * image.scale, y: visible.minY * image.scale,
                            width: visible.width * image.scale, height: visible.height * image.scale)
        guard let cropped = image.cgImage?.cropping(to: pixels) else {
            XCTFail("Could not crop the screenshot")
            return
        }
        let attachment = XCTAttachment(image: UIImage(cgImage: cropped, scale: image.scale, orientation: .up))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Asking (#452)

/// The scripted model (`AskUITestFixture`) makes real tool calls on the seeded printer and joins.
@MainActor
final class AskUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_ASK": "answer"]
    }

    func testThePrinterQuestionIsAnsweredWithACitationThatOpensTheDevice() {
        openAsk()
        ask("Is the printer up?")

        let answer = waitForAnswer("UITest Printer is offline.")
        let marker = ui("ask_label_generated")
        requireExists(marker, message: "The generated marker should show under the answer")
        let citation = ui("ask_citation_device_1")
        requireExists(citation, message: "The printer the tool returned should be cited")
        XCTAssertTrue(citation.label.contains("UITest Printer"), "Citation: \(citation.label)")
        keep([answer, marker, citation], named: "ask-printer-answer")

        citation.tap()
        // Detail found the saved row: its header shows the printer's name, not "Device Not Found".
        let name = ui("deviceDetail_label_displayName")
        requireExists(name, timeout: 8, message: "The cited printer's detail should open")
        XCTAssertEqual(name.label, "UITest Printer")
        XCTAssertFalse(ui("deviceDetail_label_notFound").exists, "Detail should find the saved printer")
        keep([name, ui("deviceDetail_image_deviceType")], named: "ask-printer-detail")
    }

    func testWhatJoinedThisWeekListsTheSeededJoins() {
        openAsk()
        ask("What joined this week?")

        let answer = waitForAnswer("Two devices joined this week: UITest Camera and UITest Speaker.")
        let first = ui("ask_citation_event_1")
        let second = ui("ask_citation_event_2")
        requireExists(first, message: "The newer join should be cited")
        requireExists(second, message: "The older join should be cited")
        XCTAssertTrue(first.label.contains("UITest Camera"), "First: \(first.label)")
        XCTAssertTrue(second.label.contains("UITest Speaker"), "Second: \(second.label)")
        keep([answer, first, second], named: "ask-joined-answer")

        // The event opens the Timeline at its day.
        first.tap()
        requireExists(ui("screen_networkTimeline"), timeout: 8, message: "The cited event should open the Timeline")
        let row = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "UITest Camera")).firstMatch
        requireExists(row, timeout: 8, message: "The Timeline should show the cited join")
        keep([row], named: "ask-joined-timeline")
    }
}

/// The printer question waits until cancelled.
@MainActor
final class AskCancelUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_ASK": "hold"]
    }

    func testCancelStopsTheQuestion() {
        openAsk()
        ask("Is the printer up?")
        requireExists(ui("ask_button_cancel"), timeout: 8, message: "Cancel should be offered while asking").tap()
        let message = ui("ask_label_message")
        requireExists(message, timeout: 8, message: "A cancelled message should show")
        XCTAssertEqual(message.label, "Cancelled.")
        XCTAssertFalse(ui("ask_label_answer").exists, "No answer should show after cancelling")
    }
}

/// Without the model, Tools has no Ask card.
@MainActor
final class AskUnavailableUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_ASK": "unavailable"]
    }

    func testTheAskCardIsHidden() {
        app.tabBars.buttons["Tools"].tap()
        let tools = ui("screen_tools")
        requireExists(tools, timeout: 8, message: "Tools screen should open")
        // Ask would sit after Room Scanner, the last Monitoring tool; the grid is lazy, so scroll to it.
        let roomScanner = ui("tools_card_room_scanner")
        for _ in 0 ..< 8 where !(roomScanner.exists && roomScanner.isHittable) {
            tools.swipeUp()
        }
        requireExists(roomScanner, timeout: 8, message: "The Monitoring tools should show")
        XCTAssertFalse(ui("tools_card_ask").exists, "The Ask card should be hidden without the model")
    }
}
