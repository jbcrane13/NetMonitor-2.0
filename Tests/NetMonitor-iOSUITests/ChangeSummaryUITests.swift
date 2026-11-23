import XCTest

// MARK: - Shared steps

private extension IOSUITestCase {
    func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    func openDashboard() {
        requireExists(app.tabBars.buttons["Dashboard"], message: "Dashboard tab should exist").tap()
        requireExists(ui("screen_dashboard"), timeout: 8, message: "Dashboard should open")
    }

    func openTimeline() {
        requireExists(app.tabBars.buttons["Timeline"], message: "Timeline tab should exist").tap()
        requireExists(ui("screen_networkTimeline"), timeout: 8, message: "Timeline should open")
        requireExists(app.staticTexts["Device Left: 192.168.1.30"], timeout: 8, message: "Timeline should list the seeded events")
    }

    func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Model answers (#453)

/// Seeded events (2 devices joined, 1 left, seconds ago) with a stand-in model that answers.
@MainActor
final class ChangeSummaryUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_INSIGHT": "answer", "UITEST_SEED_EVENTS": "1"]
    }

    func testDashboardShowsTheBriefAndTimelineSummarizesToday() {
        openDashboard()

        let card = ui("dashboard_card_changeBrief")
        requireExists(card, timeout: 30, message: "The since-yesterday brief should appear on the dashboard")
        let keyPoints = ui("dashboard_list_changeBriefKeyPoints")
        requireExists(keyPoints, message: "The brief should show the app's key points")
        XCTAssertTrue(keyPoints.label.contains("2 devices joined the network."), "Key points: \(keyPoints.label)")
        XCTAssertTrue(keyPoints.label.contains("1 device left the network."), "Key points: \(keyPoints.label)")
        let text = ui("dashboard_label_changeBriefText")
        requireExists(text, message: "The brief should show the model's text")
        XCTAssertTrue(text.label.contains("the key points above say what needs attention"), "Brief text: \(text.label)")
        let marker = ui("dashboard_label_changeBriefGenerated")
        requireExists(marker, message: "The brief should be marked as generated")
        XCTAssertTrue(marker.label.contains("Written by the on-device model"), "Marker: \(marker.label)")
        keepScreenshot(named: "dashboard-change-brief")

        openTimeline()
        let summarize = ui("timeline_button_summarize_Today")
        requireExists(summarize, timeout: 8, message: "Today's section should offer Summarize").tap()

        let summaryText = ui("timeline_label_summary_Today")
        requireExists(summaryText, timeout: 30, message: "Today's summary should appear under the header")
        XCTAssertTrue(summaryText.label.contains("the key points above say what needs attention"), "Summary: \(summaryText.label)")
        requireExists(ui("timeline_label_summaryGenerated_Today"), message: "The summary should be marked as generated")
        let summaryPoints = ui("timeline_list_summaryKeyPoints_Today")
        XCTAssertTrue(summaryPoints.label.contains("2 devices joined the network."), "Key points: \(summaryPoints.label)")
        keepScreenshot(named: "timeline-today-summary")
    }
}

// MARK: - Model unavailable (#453)

/// The same seeded events, with the model unavailable: no brief and no Summarize action.
@MainActor
final class ChangeSummaryNoModelUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_INSIGHT": "unavailable", "UITEST_SEED_EVENTS": "1"]
    }

    func testNoBriefAndNoSummarizeWithoutTheModel() {
        openDashboard()
        // Give the brief the time it would take to appear if the model answered.
        XCTAssertFalse(ui("dashboard_card_changeBrief").waitForExistence(timeout: 8), "No brief without the model")
        keepScreenshot(named: "dashboard-no-model")

        openTimeline()
        XCTAssertFalse(ui("timeline_button_summarize_Today").exists, "No Summarize action without the model")
        keepScreenshot(named: "timeline-no-model")
    }
}
