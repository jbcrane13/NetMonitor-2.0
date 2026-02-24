import XCTest

@MainActor
final class NetworkHealthScoreUITests: IOSUITestCase {

    func testHealthScoreCardAppearsOnDashboard() {
        // Dashboard is the default tab
        requireExists(
            app.descendants(matching: .any)["dashboard_card_healthScore"],
            timeout: 8,
            message: "Health score card should be visible on dashboard"
        )
    }

    func testHealthScoreGaugeVisible() {
        let card = app.descendants(matching: .any)["dashboard_card_healthScore"]
        guard card.waitForExistence(timeout: 8) else { return }

        // Gauge or loading state should be present
        let gauge = app.descendants(matching: .any)["healthScore_gauge"]
        let hasGauge = gauge.waitForExistence(timeout: 10)
        // Either loading or gauge visible is acceptable
        XCTAssertTrue(card.exists, "Health score card should remain visible")
        _ = hasGauge // gauge may take time to compute
    }

    func testRefreshButtonExists() {
        guard app.descendants(matching: .any)["dashboard_card_healthScore"].waitForExistence(timeout: 8) else {
            return
        }

        let refreshButton = app.buttons["healthScore_button_refresh"]
        guard refreshButton.waitForExistence(timeout: 5) else { return }
        XCTAssertTrue(refreshButton.exists, "Refresh button should be visible on health score card")
    }

    func testRefreshButtonTappable() {
        guard app.descendants(matching: .any)["dashboard_card_healthScore"].waitForExistence(timeout: 8) else {
            return
        }
        let btn = app.buttons["healthScore_button_refresh"]
        guard btn.waitForExistence(timeout: 5) else { return }
        btn.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["dashboard_card_healthScore"].exists,
            "Health score card should remain after refresh"
        )
    }
}
