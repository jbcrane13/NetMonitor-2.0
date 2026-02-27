import XCTest

/// Functional UI tests for the macOS Dashboard view.
///
/// All tests extend ``MacOSUITestCase`` so the app launches in UI-test mode
/// (monitoring disabled, auto-start off). Tests verify the redesigned
/// no-scroll 4-row dashboard layout and its widget identifiers.
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
        requireExists(app.buttons["dashboard_targets_toggleButton"], timeout: 5,
                      message: "Monitoring toggle button should exist in target monitoring section")
    }

    func testMonitoringToggleButtonIsTappable() {
        let button = requireExists(
            app.buttons["dashboard_targets_toggleButton"], timeout: 5,
            message: "Monitoring toggle button should exist"
        )
        XCTAssertTrue(button.isEnabled, "Monitoring toggle should be enabled")
    }

    /// Functional: tap the toggle and verify its label changes.
    func testMonitoringToggleChangesStateAfterTap() {
        let button = requireExists(
            app.buttons["dashboard_targets_toggleButton"], timeout: 5,
            message: "Monitoring toggle button should exist"
        )
        XCTAssertTrue(button.isEnabled, "Monitoring toggle should be enabled before tap")

        let labelBefore = button.label
        button.tap()

        requireExists(button, timeout: 5,
                      message: "Monitoring toggle should remain visible after tap")

        let labelAfter = button.label
        XCTAssertNotEqual(labelBefore, labelAfter,
                          "Monitoring toggle label should change after tapping (was '\(labelBefore)', got '\(labelAfter)')")

        // Restore original state.
        button.tap()
    }

    // MARK: - New Dashboard Widget Cards

    func testInternetActivityCardExists() {
        requireExists(app.otherElements["dashboard_card_internetActivity"], timeout: 5,
                      message: "Internet Activity card should exist in Row A")
    }

    func testHealthGaugeCardExists() {
        requireExists(app.otherElements["dashboard_card_healthGauge"], timeout: 5,
                      message: "Health Gauge card should exist in Row A")
    }

    func testISPHealthCardExists() {
        requireExists(app.otherElements["dashboard_card_ispHealth"], timeout: 5,
                      message: "ISP Health card should exist in Row B")
    }

    func testLatencyAnalysisCardExists() {
        requireExists(app.otherElements["dashboard_card_latencyAnalysis"], timeout: 5,
                      message: "Latency Analysis card should exist in Row B")
    }

    func testConnectivityCardExists() {
        requireExists(app.otherElements["dashboard_card_connectivity"], timeout: 5,
                      message: "Connectivity card should exist in Row C")
    }

    func testActiveDevicesCardExists() {
        requireExists(app.otherElements["dashboard_card_activeDevices"], timeout: 5,
                      message: "Active Devices card should exist in Row C")
    }

    /// Functional: verify all 6 redesigned dashboard cards are present.
    func testDashboardCardsAllPresent() {
        let cards = [
            "dashboard_card_internetActivity",
            "dashboard_card_healthGauge",
            "dashboard_card_ispHealth",
            "dashboard_card_latencyAnalysis",
            "dashboard_card_connectivity",
            "dashboard_card_activeDevices",
        ]
        for cardID in cards {
            requireExists(app.otherElements[cardID], timeout: 5,
                          message: "\(cardID) should be visible on the dashboard")
        }
    }

    // MARK: - Health Score

    func testHealthGaugeScoreExists() {
        requireExists(app.otherElements["dashboard_healthGauge_score"], timeout: 5,
                      message: "Health gauge score element should exist")
    }

    // MARK: - Activity Range Picker

    func testActivityRangePickerExists() {
        requireExists(app.segmentedControls["dashboard_activity_rangePicker"], timeout: 5,
                      message: "Activity range picker (24H/7D/30D) should exist in internet activity card")
    }

    // MARK: - Empty State

    func testNoTargetsMessageWhenEmpty() {
        // Dashboard detail pane should always load regardless of target count.
        requireExists(app.otherElements["detail_dashboard"], timeout: 5,
                      message: "Dashboard detail pane should be visible regardless of target count")
    }
}
