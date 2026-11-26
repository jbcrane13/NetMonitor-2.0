import XCTest

// MARK: - Shared steps

private extension IOSUITestCase {
    var healthCard: XCUIElement { app.byID("dashboard_card_healthScore") }
    /// The sparkline row's caption, which only exists while the chart does.
    var trendLabel: XCUIElement { app.staticTexts["TREND"] }

    func openDashboardHealthCard() {
        requireExists(app.tabBars.buttons["Dashboard"], message: "Dashboard tab should exist").tap()
        requireExists(healthCard, timeout: 10, message: "The health card should be on the dashboard")
    }

    func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Five saved samples (#491 S5)

/// Five seeded health samples for the dashboard's network: the card shows the trend sparkline.
@MainActor
final class HealthHistoryUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_SEED_HEALTH_SAMPLES": "5"]
    }

    func testDashboardHealthCardShowsTheHistorySparkline() {
        openDashboardHealthCard()
        requireExists(trendLabel, timeout: 20, message: "The health card should show the history sparkline")
        let chart = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Health score history'")).firstMatch
        requireExists(chart, message: "The sparkline should be on screen")
        XCTAssertEqual(chart.value as? String, "5 samples", "The chart should plot the five seeded samples")
        keepScreenshot(named: "dashboard-health-history-5-samples")
    }
}

// MARK: - One saved sample (#491 S5)

/// One seeded sample: not enough for a line, so no sparkline.
@MainActor
final class HealthHistorySingleSampleUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_SEED_HEALTH_SAMPLES": "1"]
    }

    func testDashboardHealthCardHasNoSparklineWithOneSample() {
        openDashboardHealthCard()
        // The dashboard's own health refresh (five pings) finishes well inside this window. Its
        // sample must be throttled, or the card would reach two samples and draw the line.
        let chart = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Health score history'")).firstMatch
        XCTAssertFalse(chart.waitForExistence(timeout: 20), "One sample should not draw a sparkline")
        XCTAssertFalse(trendLabel.exists, "One sample should not draw a sparkline")
        keepScreenshot(named: "dashboard-health-history-1-sample")
    }
}
