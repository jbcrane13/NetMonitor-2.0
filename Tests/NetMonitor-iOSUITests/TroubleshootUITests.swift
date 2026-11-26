import XCTest

// MARK: - Shared steps

private extension IOSUITestCase {
    func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Opens Tools → Troubleshoot.
    func openTroubleshooter() {
        app.tabBars.buttons["Tools"].tap()
        let tools = ui("screen_tools")
        requireExists(tools, timeout: 8, message: "Tools screen should open")
        let card = ui("tools_card_troubleshoot")
        for _ in 0 ..< 6 where !(card.exists && card.isHittable) {
            tools.swipeUp()
        }
        requireExists(card, timeout: 8, message: "Troubleshoot card should be in the Diagnostics tools").tap()
        requireExists(ui("troubleshoot_field_symptom"), timeout: 8, message: "The symptom field should show when the model is available")
    }

    /// Scrolls the troubleshooter until `element` is on screen.
    func scrollTo(_ element: XCUIElement) {
        let screen = ui("screen_troubleshootTool")
        for _ in 0 ..< 6 where !(element.exists && element.isHittable) {
            screen.swipeUp()
        }
    }

    /// Types `symptom` and taps Start.
    func describe(_ symptom: String) {
        let field = ui("troubleshoot_field_symptom")
        field.tap()
        field.typeText(symptom)
        requireExists(ui("troubleshoot_button_start"), message: "Start should be offered").tap()
    }

    /// Keeps a screenshot cropped to `parts`, so no other screen content goes into the evidence.
    func keep(_ parts: [XCUIElement], named name: String) {
        let image = app.screenshot().image
        let frame = parts.map(\.frame).reduce(parts[0].frame) { $0.union($1) }.insetBy(dx: -12, dy: -12)
        let screen = CGRect(origin: .zero, size: image.size)
        let visible = frame.intersection(screen)
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

// MARK: - The Zoom flow (#451)

@MainActor
final class TroubleshootUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_TROUBLESHOOT": "answer"]
    }

    func testZoomFreezingRunsTheChecksAndRanksWeakSignalFirst() {
        openTroubleshooter()
        describe("Zoom keeps freezing")

        // The slow-internet script: router ping, DNS, Wi-Fi, speed test, each with its raw result.
        let lastStep = ui("troubleshoot_step_4")
        requireExists(lastStep, timeout: 10, message: "The four steps of the slow-internet script should show")
        let deadline = Date().addingTimeInterval(20)
        while !lastStep.label.contains("Download 85 Mbps"), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(ui("troubleshoot_step_1").label.contains("9 of 10 replies"), "Step 1: \(ui("troubleshoot_step_1").label)")
        XCTAssertTrue(ui("troubleshoot_step_2").label.contains("apple.com resolved in 38 ms"), "Step 2: \(ui("troubleshoot_step_2").label)")
        XCTAssertTrue(ui("troubleshoot_step_3").label.contains("Signal -80 dBm"), "Step 3: \(ui("troubleshoot_step_3").label)")
        XCTAssertTrue(lastStep.label.contains("Download 85 Mbps"), "Step 4: \(lastStep.label)")
        scrollTo(lastStep)
        keep([ui("troubleshoot_step_1"), lastStep], named: "troubleshoot-zoom-steps")

        let first = ui("troubleshoot_finding_1")
        requireExists(first, timeout: 10, message: "The likely causes should show")
        XCTAssertTrue(first.label.contains("Weak signal"), "First finding: \(first.label)")
        XCTAssertTrue(ui("troubleshoot_finding_2").label.contains("Packet loss to your router"), "Second: \(ui("troubleshoot_finding_2").label)")

        let explanation = ui("troubleshoot_label_explanation")
        requireExists(explanation, timeout: 20, message: "The model's explanation should show")
        XCTAssertTrue(explanation.label.contains("signal is weak"), "Explanation: \(explanation.label)")
        let marker = ui("troubleshoot_label_generated")
        requireExists(marker, message: "The explanation should be marked as generated")
        XCTAssertTrue(marker.label.contains("Written by the on-device model"), "Marker: \(marker.label)")

        scrollTo(marker)
        keep([first, ui("troubleshoot_finding_2")], named: "troubleshoot-zoom-findings")
        keep([explanation, marker], named: "troubleshoot-zoom-explanation")
        captureScreenshot(named: "troubleshoot-zoom-screen")
    }
}

// MARK: - Cancel during step 2 (#451)

@MainActor
final class TroubleshootCancelUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_TROUBLESHOOT": "hold"]
    }

    func testCancellingDuringStepTwoKeepsTheResultsSoFar() {
        openTroubleshooter()
        describe("Zoom keeps freezing")

        let step2 = ui("troubleshoot_step_2")
        requireExists(step2, timeout: 10, message: "Step 2 should show")
        let deadline = Date().addingTimeInterval(10)
        while !step2.label.contains("Running"), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(step2.label.contains("Running"), "Step 2 should be running: \(step2.label)")
        requireExists(ui("troubleshoot_button_cancel"), message: "Cancel should be offered while the checks run").tap()

        let message = ui("troubleshoot_label_message")
        requireExists(message, timeout: 10, message: "A cancelled run should say so")
        XCTAssertTrue(message.label.contains("Cancelled"), "Message: \(message.label)")
        let step1 = ui("troubleshoot_step_1")
        XCTAssertTrue(step1.label.contains("9 of 10 replies"), "Step 1's result should remain: \(step1.label)")
        XCTAssertTrue(step2.label.contains("Not run"), "Step 2: \(step2.label)")
        XCTAssertTrue(ui("troubleshoot_step_4").label.contains("Not run"), "Step 4: \(ui("troubleshoot_step_4").label)")
        // The measured loss still names its cause, but no all-clear and no model text.
        XCTAssertTrue(ui("troubleshoot_finding_1").label.contains("Packet loss to your router"), "Finding: \(ui("troubleshoot_finding_1").label)")
        XCTAssertFalse(ui("troubleshoot_label_explanation").exists, "A cancelled run is not explained")

        keep([message], named: "troubleshoot-cancelled-message")
        scrollTo(ui("troubleshoot_finding_1"))
        keep([step1, ui("troubleshoot_step_4"), ui("troubleshoot_finding_1")], named: "troubleshoot-cancelled-steps")
        captureScreenshot(named: "troubleshoot-cancelled-screen")
    }
}

// MARK: - Modem lights from a photo (#558)

/// The simulator has no camera, so `UITEST_MODEM_IMAGE=1` gives the sheet a drawn modem panel
/// (POWER, DSL, WI-FI and LAN 1 green, INTERNET red, LAN 2 off), and `UITEST_MODEM_MODEL=answer`
/// stands in for the on-device model: it reads those lights and words the app's meanings. The
/// wording still goes through `InsightSummarizer`'s checks.
@MainActor
final class ModemLightsUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_TROUBLESHOOT": "answer", "UITEST_MODEM_IMAGE": "1", "UITEST_MODEM_MODEL": "answer"]
    }

    func testAPhotoOfTheModemNamesTheRedInternetLight() {
        openTroubleshooter()
        let entry = ui("troubleshoot_button_modemLights")
        scrollTo(entry)
        requireExists(entry, timeout: 5, message: "Troubleshoot should offer to read the modem's lights").tap()

        let headline = ui("modemLights_label_headline")
        requireExists(headline, timeout: 15, message: "The lights should be read from the photo")
        XCTAssertEqual(headline.label, "1 light shows a problem.")
        let internet = ui("modemLights_row_2")
        XCTAssertTrue(internet.label.contains("INTERNET: red"), "Row 3: \(internet.label)")
        XCTAssertTrue(internet.label.contains("Internet light is red: the modem has no internet connection."), "Row 3: \(internet.label)")
        // Off is a check worded as a question, never a problem (#558 option A).
        let lan2 = ui("modemLights_row_5").label
        XCTAssertTrue(lan2.contains("LAN 2: reads as off"), "LAN 2: \(lan2)")
        XCTAssertTrue(lan2.contains("Ethernet 2 reads as off. If it is dark, nothing is connected to that port"), "LAN 2: \(lan2)")
        XCTAssertTrue(ui("modemLights_label_blinking").label.contains("blinking can't be seen in one photo"))
        XCTAssertEqual(ui("modemLights_label_whiteNote").label, "White lights on a light-coloured case may read as off.")

        let explanation = ui("modemLights_label_explanation")
        requireExists(explanation, timeout: 15, message: "The model's wording should show")
        XCTAssertTrue(explanation.label.contains("no internet connection"), "Explanation: \(explanation.label)")
        let marker = ui("modemLights_label_generated")
        XCTAssertTrue(marker.label.contains("Written by the on-device model"), "Marker: \(marker.label)")

        keep([headline, ui("modemLights_label_whiteNote")], named: "modem-lights-reading")
        let screen = ui("modemLights_button_retake")
        scrollTo(screen)
        keep([explanation, marker], named: "modem-lights-explanation")
        captureScreenshot(named: "modem-lights-screen")
    }
}

@MainActor
final class ModemLightsUnwrittenUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_TROUBLESHOOT": "answer", "UITEST_MODEM_IMAGE": "1", "UITEST_MODEM_MODEL": "unwritten"]
    }

    func testWithoutWordingTheAppsLinesStillShow() {
        openTroubleshooter()
        let entry = ui("troubleshoot_button_modemLights")
        scrollTo(entry)
        requireExists(entry, timeout: 5, message: "The reader should be offered").tap()
        let headline = ui("modemLights_label_headline")
        requireExists(headline, timeout: 15, message: "The lights should be read")
        XCTAssertTrue(ui("modemLights_row_2").label.contains("the modem has no internet connection"))
        XCTAssertFalse(ui("modemLights_label_explanation").exists, "Nothing is worded without the text model")
        keep([headline, ui("modemLights_label_whiteNote")], named: "modem-lights-unworded")
    }
}

@MainActor
final class ModemLightsUnavailableUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_TROUBLESHOOT": "answer", "UITEST_MODEM_MODEL": "unavailable"]
    }

    func testWithoutAVisionModelTheReaderIsHidden() {
        openTroubleshooter()
        scrollTo(ui("troubleshoot_button_kind_websiteNotLoading"))
        XCTAssertFalse(ui("troubleshoot_button_modemLights").exists, "No reader without a model that sees images")
    }
}
