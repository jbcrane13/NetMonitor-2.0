import XCTest

// MARK: - Shared steps

private extension IOSUITestCase {
    func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Opens the seeded weak-corner survey from Tools → Wi-Fi Heatmap → Open Survey.
    func openSeededSurvey() {
        app.tabBars.buttons["Tools"].tap()
        // ToolsView lowercases the tool name, hyphen included. The card is in a lazy grid
        // below the fold, so swipe the Tools screen itself until it is on screen.
        let card = ui("tools_card_wi-fi_heatmap").firstMatch
        let tools = ui("screen_tools")
        requireExists(tools, timeout: 8, message: "Tools screen should open")
        for _ in 0 ..< 6 where !(card.exists && card.isHittable) {
            tools.swipeUp()
        }
        requireExists(card, timeout: 8, message: "Wi-Fi Heatmap card should exist in tools grid").tap()
        requireExists(ui("screen_heatmapSurvey"), timeout: 8, message: "Heatmap survey screen should appear")
        let skip = ui("shortcutSetup_button_skip")
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
            _ = waitForDisappearance(skip, timeout: 3)
        }
        // The survey screen's identifier is stamped over its children's, so match by text.
        requireExists(app.buttons["Open Saved Survey"].firstMatch, timeout: 5, message: "Open Survey should be offered").tap()
        requireExists(app.staticTexts["UITest Weak Corner"].firstMatch, timeout: 8, message: "The seeded survey should be listed").tap()
    }

    /// The advisor card, with its key points checked.
    func requireAdvisorKeyPoints() -> XCUIElement {
        let card = ui("heatmap_card_advisor")
        requireExists(card, timeout: 20, message: "The advisor card should appear on the survey result")
        let keyPoints = ui("heatmap_list_advisorKeyPoints")
        requireExists(keyPoints, message: "The advisor should show the app's key points")
        XCTAssertTrue(keyPoints.label.contains("The north-east corner is weak ("), "Key points: \(keyPoints.label)")
        XCTAssertTrue(
            keyPoints.label.contains("Try moving the access point toward the north-east corner."),
            "Key points: \(keyPoints.label)"
        )
        return card
    }

    /// Keeps a screenshot cropped to the card's `parts`, so no other screen content goes into
    /// the evidence.
    func keepCard(_ parts: [XCUIElement], named name: String) {
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

// MARK: - Model answers (#455)

@MainActor
final class HeatmapAdvisorUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_INSIGHT": "answer", "UITEST_SEED_HEATMAP": "1"]
    }

    func testFinishedSurveyShowsTheAdvisorWithTheModelsText() {
        openSeededSurvey()

        let card = requireAdvisorKeyPoints()
        let text = ui("heatmap_label_advisorText")
        requireExists(text, timeout: 20, message: "The advisor should show the model's text")
        XCTAssertTrue(text.label.contains("where the signal is weak"), "Advisor text: \(text.label)")
        let marker = ui("heatmap_label_advisorGenerated")
        requireExists(marker, message: "The advisor text should be marked as generated")
        XCTAssertTrue(marker.label.contains("Written by the on-device model"), "Marker: \(marker.label)")
        keepCard([card, ui("heatmap_list_advisorKeyPoints"), text, marker], named: "heatmap-advisor-answer")
        // The whole screen, for checking the card leaves the heatmap visible; not for publishing.
        captureScreenshot(named: "heatmap-advisor-answer-screen")
    }
}

// MARK: - Model unavailable (#455)

@MainActor
final class HeatmapAdvisorUnavailableUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_INSIGHT": "unavailable", "UITEST_SEED_HEATMAP": "1"]
    }

    func testFinishedSurveyShowsOnlyTheKeyPointsWithoutTheModel() {
        openSeededSurvey()

        let card = requireAdvisorKeyPoints()
        // Long enough for an answer to have arrived, had one been asked for.
        sleep(2)
        XCTAssertFalse(ui("heatmap_label_advisorText").exists, "No model text without the model")
        XCTAssertFalse(ui("heatmap_label_advisorGenerated").exists, "No generated marker without model text")
        keepCard([card, ui("heatmap_list_advisorKeyPoints")], named: "heatmap-advisor-unavailable")
    }
}
