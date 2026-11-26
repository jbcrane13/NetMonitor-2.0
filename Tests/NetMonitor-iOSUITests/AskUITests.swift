import XCTest

// MARK: - Shared steps

private extension IOSUITestCase {
    func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Opens Tools → Ask, in Monitoring.
    func openAsk() {
        let tools = ui("screen_tools")
        // Right after a scan the first tap can be swallowed (a dismissed prompt); tap again.
        for _ in 0 ..< 3 where !tools.exists {
            app.tabBars.buttons["Tools"].tap()
            _ = tools.waitForExistence(timeout: 4)
        }
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

        let answer = waitForAnswer("UITest Printer is a printer at 192.0.2.57.")
        let marker = ui("ask_label_generated")
        requireExists(marker, message: "The generated marker should show under the answer")
        let citation = ui("ask_citation_device_1")
        requireExists(citation, message: "The printer the tool returned should be cited")
        XCTAssertTrue(citation.label.contains("UITest Printer"), "Citation: \(citation.label)")
        // The app's status beside it: this network has no scan.
        XCTAssertTrue(citation.label.contains("Not checked recently"), "Citation: \(citation.label)")
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

    func testAnOlderEventCitationScrollsTheTimelineToItsDay() {
        openAsk()
        ask("What joined this month?")

        _ = waitForAnswer("Three devices joined in the last 30 days: UITest Camera, UITest Speaker and UITest Doorbell.")
        let oldest = ui("ask_citation_event_3")
        requireExists(oldest, message: "The join 20 days ago should be cited third")
        XCTAssertTrue(oldest.label.contains("UITest Doorbell"), "Third: \(oldest.label)")

        oldest.tap()
        requireExists(ui("screen_networkTimeline"), timeout: 8, message: "The cited event should open the Timeline")
        // 17 days of filler events sit above it: only the scroll to its day brings it on screen.
        let row = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "UITest Doorbell")).firstMatch
        requireExists(row, timeout: 8, message: "The Timeline should show the cited join")
        let hittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: row)
        wait(for: [hittable], timeout: 8)
        keep([row], named: "ask-older-event-timeline")
    }

    // MARK: - Live tools (#579)

    /// The seeded printer is offline and this network has no scan: the app refuses to ping it and
    /// says to scan first. The model's "Yes, … is answering" is dropped; the saved status beside
    /// the citation stays the scan's.
    func testAPingBeforeAnyScanIsRefusedByTheApp() {
        openAsk()
        ask("Is the printer answering right now?")

        let answer = waitForAnswer("It is a printer.")
        let line = ui("ask_label_measurement_1")
        requireExists(line, message: "The app's refusal should show under the answer")
        XCTAssertEqual(line.label,
                       "UITest Printer (192.0.2.57): not pinged. Run a scan first: this network hasn't been checked since you joined it.")
        XCTAssertFalse(line.label.contains("measured at"), "A refusal is not a measurement: \(line.label)")
        let citation = ui("ask_citation_device_1")
        requireExists(citation, message: "The printer should be cited")
        XCTAssertTrue(citation.label.contains("Not checked recently"), "The saved status stays the scan's: \(citation.label)")
        keep([answer, line, citation], named: "ask-ping-refused")
    }

    func testTheConnectionQuestionShowsTheAppsStatusLine() {
        openAsk()
        ask("How is my connection?")

        let answer = waitForAnswer("The connection is Wi-Fi.")
        let measurement = ui("ask_label_measurement_1")
        requireExists(measurement, message: "The app's connection measurement should show under the answer")
        XCTAssertTrue(measurement.label.hasPrefix(
            "Wi-Fi · gateway: 3 of 3 replies, 2 ms average · internet (8.8.8.8): 3 of 3 replies, 15 ms average, measured at "
        ), "Measurement: \(measurement.label)")
        keep([answer, measurement], named: "ask-connection-measurement")
    }
}

/// #452 after #589: the fake scan saves uitest-device-0…4 on the UI-test network, and "What's
/// online?" answers from those rows with how fresh they are.
@MainActor
final class AskFreshnessUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_ASK": "answer", "UITEST_FAKE_DEVICES": "1"]
    }

    /// Scans from the Map tab and waits for it to finish.
    private func scan() {
        requireExists(app.tabBars.buttons["Map"], timeout: 10, message: "The Map tab should exist").tap()
        requireExists(ui("networkMap_button_scan"), timeout: 10, message: "The map's Scan button should exist").tap()
        let spinner = app.activityIndicators.firstMatch
        _ = spinner.waitForExistence(timeout: 3)
        XCTAssertTrue(waitForDisappearance(spinner, timeout: 20), "The scan should finish")
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2) {
            notNow.tap()
        }
    }

    func testWhatsOnlineSaysHowFreshTheScanIs() {
        scan()
        openAsk()
        ask("What's online?")

        // The model's "Online as of the scan …: …" is dropped: the app says it, and shows each status.
        let answer = ui("ask_label_answer")
        requireExists(answer, timeout: 10, message: "An answer should show")
        let worded = expectation(
            for: NSPredicate(format: "label MATCHES %@", "[0-9]+ of [0-9]+ devices are online as of the scan .* ago\\."), evaluatedWith: answer
        )
        wait(for: [worded], timeout: 10)
        XCTAssertFalse(ui("ask_label_generated").exists, "The app's summary is not marked as generated")
        let online = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "ask_citation_device_", "Online"))
        XCTAssertGreaterThan(online.count, 0, "The devices that answered should show Online")
        let freshness = ui("ask_label_freshness")
        requireExists(freshness, message: "The app's freshness line should show under the answer")
        XCTAssertTrue(freshness.label.contains("Device status as of the scan "), "Freshness: \(freshness.label)")
        XCTAssertTrue(freshness.label.contains("less than a minute ago") || freshness.label.contains("minute ago")
            || freshness.label.contains("minutes ago"), "Freshness: \(freshness.label)")
        let citation = ui("ask_citation_device_1")
        requireExists(citation, message: "The listed devices should be cited")
        XCTAssertTrue(citation.label.contains("Last seen"), "Citation: \(citation.label)")
        keep([answer, freshness, citation], named: "ask-online-freshness")

        // The citation opens the saved row by its id.
        let cited = citation.label
        citation.tap()
        let title = ui("deviceDetail_label_displayName")
        requireExists(title, timeout: 8, message: "The cited device's detail should open")
        XCTAssertTrue(cited.contains(title.label), "Detail \(title.label) for citation \(cited)")
        XCTAssertFalse(ui("deviceDetail_label_notFound").exists, "Detail should find the saved device")
    }
}

/// As `AskFreshnessUITests`, with `UITEST_SCAN_CLOCK=1`: the scan is stamped 2026-11-20, long before
/// now, so it isn't recent. The scripted model calls the devices online, as the real model did; the
/// app drops that and says the devices haven't been checked recently.
@MainActor
final class AskStaleUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_ASK": "answer", "UITEST_FAKE_DEVICES": "1", "UITEST_SCAN_CLOCK": "1"]
    }

    func testWhatsOnlineAfterAnOldScanSaysTheDevicesHaventBeenChecked() {
        requireExists(app.tabBars.buttons["Map"], timeout: 10, message: "The Map tab should exist").tap()
        requireExists(ui("networkMap_button_scan"), timeout: 10, message: "The map's Scan button should exist").tap()
        let spinner = app.activityIndicators.firstMatch
        _ = spinner.waitForExistence(timeout: 3)
        XCTAssertTrue(waitForDisappearance(spinner, timeout: 20), "The scan should finish")
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2) {
            notNow.tap()
        }
        openAsk()
        ask("What's online?")

        let answer = waitForAnswer("These devices haven't been checked recently. Their last-seen times are below.")
        XCTAssertFalse(ui("ask_label_generated").exists, "The app's own words are not marked as generated")
        let freshness = ui("ask_label_freshness")
        requireExists(freshness, message: "The freshness line should still show")
        XCTAssertTrue(freshness.label.contains("Not checked recently: the last scan was"), "Freshness: \(freshness.label)")
        let citation = ui("ask_citation_device_1")
        requireExists(citation, message: "The devices looked up should still be cited")
        XCTAssertTrue(citation.label.contains("Last seen"), "Citation: \(citation.label)")
        keep([answer, freshness, citation], named: "ask-online-stale")
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

/// #579 review: after a scan of the fake network, an Online device is pinged through the fixture's
/// fake pinger. The model's "It pinged fine." is about the live result, so the app's line is the
/// answer, with the address it pinged.
@MainActor
final class AskLiveUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_ASK": "answer", "UITEST_FAKE_DEVICES": "1"]
    }

    func testAPingAfterAScanShowsTheAppsMeasurement() {
        requireExists(app.tabBars.buttons["Map"], timeout: 10, message: "The Map tab should exist").tap()
        requireExists(ui("networkMap_button_scan"), timeout: 10, message: "The map's Scan button should exist").tap()
        let spinner = app.activityIndicators.firstMatch
        _ = spinner.waitForExistence(timeout: 3)
        XCTAssertTrue(waitForDisappearance(spinner, timeout: 20), "The scan should finish")
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2) {
            notNow.tap()
        }
        openAsk()
        ask("Is 192.168.1.10 answering right now?")

        let answer = waitForAnswer("The app's live check is below.")
        let line = ui("ask_label_measurement_1")
        requireExists(line, message: "The app's ping measurement should show under the answer")
        XCTAssertTrue(line.label.contains("(192.168.1.10): 3 of 3 replies, 4 ms average, measured at "), "Measurement: \(line.label)")
        XCTAssertFalse(ui("ask_label_generated").exists, "No model text is shown, so nothing is marked as generated")
        keep([answer, line], named: "ask-ping-after-scan")
    }
}
