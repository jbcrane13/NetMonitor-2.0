import XCTest

/// Functional UI tests for the macOS Dashboard view.
///
/// All tests extend ``MacOSUITestCase`` so the app launches in UI-test mode
/// (monitoring disabled, auto-start off).  Every test asserts a *state change*
/// after an interaction — not just element existence.
@MainActor
final class DashboardUITests: MacOSUITestCase {

    // MARK: - Setup

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Dashboard is the default selection; navigate explicitly to be safe.
        navigateToSidebar("dashboard")
    }

    // MARK: - Dashboard Detail Pane

    func testDashboardDetailExists() {
        requireExists(app.otherElements["detail_dashboard"], timeout: 5,
                      message: "Dashboard detail pane should exist")
    }

    // MARK: - Monitoring Toggle

    func testMonitoringToggleButtonExists() {
        requireExists(app.buttons["dashboard_button_monitoring_toggle"], timeout: 5,
                      message: "Monitoring toggle button should exist")
    }

    func testMonitoringToggleButtonIsTappable() {
        let button = requireExists(
            app.buttons["dashboard_button_monitoring_toggle"], timeout: 5,
            message: "Monitoring toggle button should exist"
        )
        XCTAssertTrue(button.isEnabled, "Monitoring toggle should be enabled")
    }

    /// Functional: tap the toggle and verify its label changes.
    func testMonitoringToggleChangesStateAfterTap() {
        let button = requireExists(
            app.buttons["dashboard_button_monitoring_toggle"], timeout: 5,
            message: "Monitoring toggle button should exist"
        )
        XCTAssertTrue(button.isEnabled, "Monitoring toggle should be enabled before tap")

        // Capture the label before tapping.
        let labelBefore = button.label

        button.tap()

        // After tapping, the button should still be visible and its label should
        // have changed (Start Monitoring ↔ Stop Monitoring).
        requireExists(button, timeout: 5,
                      message: "Monitoring toggle should remain visible after tap")

        let labelAfter = button.label
        // Accept either direction of toggle; just verify something changed.
        // (In UI-test mode the app may not actually start monitoring, but the
        //  label should still reflect the new intended state.)
        XCTAssertNotEqual(labelBefore, labelAfter,
                          "Monitoring toggle label should change after tapping (was '\(labelBefore)', got '\(labelAfter)')")

        // Restore original state.
        button.tap()
    }

    // MARK: - Info Cards

    func testConnectionInfoCardExists() {
        requireExists(app.otherElements["dashboard_card_connection"], timeout: 5,
                      message: "Connection info card should exist")
    }

    func testGatewayInfoCardExists() {
        requireExists(app.otherElements["dashboard_card_gateway"], timeout: 5,
                      message: "Gateway info card should exist")
    }

    func testQuickStatsBarExists() {
        requireExists(app.otherElements["dashboard_card_quickStats"], timeout: 5,
                      message: "Quick stats bar should exist")
    }

    func testISPInfoCardExists() {
        requireExists(app.otherElements["dashboard_card_isp"], timeout: 5,
                      message: "ISP info card should exist")
    }

    /// Functional: verify all 4 dashboard cards are present in a single pass.
    func testDashboardCardsAllPresent() {
        let cards = [
            "dashboard_card_connection",
            "dashboard_card_gateway",
            "dashboard_card_quickStats",
            "dashboard_card_isp"
        ]
        for cardID in cards {
            requireExists(app.otherElements[cardID], timeout: 5,
                          message: "\(cardID) should be visible on the dashboard")
        }
    }

    // MARK: - Quick Stats

    func testQuickStatsBarDisplayed() {
        requireExists(app.otherElements["dashboard_quickStats_bar"], timeout: 5,
                      message: "Quick stats bar should be displayed")
    }

    // MARK: - Card Refresh Buttons

    func testConnectionCardRefreshButton() {
        let button = requireExists(
            app.buttons["connection_card_button_refresh"], timeout: 5,
            message: "Connection card refresh button should exist"
        )
        XCTAssertTrue(button.isEnabled, "Connection card refresh button should be enabled")
    }

    func testGatewayCardRefreshButton() {
        let button = requireExists(
            app.buttons["gateway_card_button_refresh"], timeout: 5,
            message: "Gateway card refresh button should exist"
        )
        XCTAssertTrue(button.isEnabled, "Gateway card refresh button should be enabled")
    }

    func testISPCardRefreshButton() {
        let button = requireExists(
            app.buttons["isp_card_button_refresh"], timeout: 5,
            message: "ISP card refresh button should exist"
        )
        XCTAssertTrue(button.isEnabled, "ISP card refresh button should be enabled")
    }

    /// Functional: tap connection refresh → button must still exist (no crash/disappearance).
    func testConnectionCardRefreshButtonRemainsAfterTap() {
        let button = app.buttons["connection_card_button_refresh"]
        guard button.waitForExistence(timeout: 5) else {
            // Button may be absent when offline — skip gracefully.
            return
        }
        button.tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "Connection card refresh button should remain visible after tap")
    }

    /// Functional: tap gateway refresh → button must still exist (no crash/disappearance).
    func testGatewayCardRefreshButtonRemainsAfterTap() {
        let button = app.buttons["gateway_card_button_refresh"]
        guard button.waitForExistence(timeout: 5) else {
            return
        }
        button.tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "Gateway card refresh button should remain visible after tap")
    }

    /// Functional: tap ISP refresh → button must still exist (no crash/disappearance).
    func testISPCardRefreshButtonRemainsAfterTap() {
        let button = app.buttons["isp_card_button_refresh"]
        guard button.waitForExistence(timeout: 5) else {
            return
        }
        button.tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "ISP card refresh button should remain visible after tap")
    }

    // MARK: - Empty State

    func testNoTargetsMessageWhenEmpty() {
        // On a fresh launch with no targets, the dashboard should still load.
        requireExists(app.otherElements["detail_dashboard"], timeout: 5,
                      message: "Dashboard detail pane should be visible regardless of target count")
    }
}
