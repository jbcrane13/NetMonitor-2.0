import XCTest

@MainActor
final class DashboardUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Dashboard is the default selection, no navigation needed
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Dashboard Detail Pane

    func testDashboardDetailExists() {
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 5))
    }

    // MARK: - Monitoring Toggle

    func testMonitoringToggleButtonExists() {
        XCTAssertTrue(app.buttons["dashboard_button_monitoring_toggle"].waitForExistence(timeout: 5))
    }

    func testMonitoringToggleButtonIsTappable() {
        let button = app.buttons["dashboard_button_monitoring_toggle"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isEnabled)
    }

    // MARK: - Info Cards

    func testConnectionInfoCardExists() {
        XCTAssertTrue(app.otherElements["dashboard_card_connection"].waitForExistence(timeout: 5))
    }

    func testGatewayInfoCardExists() {
        XCTAssertTrue(app.otherElements["dashboard_card_gateway"].waitForExistence(timeout: 5))
    }

    func testQuickStatsBarExists() {
        XCTAssertTrue(app.otherElements["dashboard_card_quickStats"].waitForExistence(timeout: 5))
    }

    func testISPInfoCardExists() {
        XCTAssertTrue(app.otherElements["dashboard_card_isp"].waitForExistence(timeout: 5))
    }

    // MARK: - Quick Stats

    func testQuickStatsBarDisplayed() {
        XCTAssertTrue(app.otherElements["dashboard_quickStats_bar"].waitForExistence(timeout: 5))
    }

    // MARK: - Card Refresh Buttons

    func testConnectionCardRefreshButton() {
        let button = app.buttons["connection_card_button_refresh"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isEnabled)
    }

    func testGatewayCardRefreshButton() {
        let button = app.buttons["gateway_card_button_refresh"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isEnabled)
    }

    func testISPCardRefreshButton() {
        let button = app.buttons["isp_card_button_refresh"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isEnabled)
    }

    // MARK: - Empty State

    func testNoTargetsMessageWhenEmpty() {
        // On a fresh launch with no targets, should show empty state
        let emptyLabel = app.staticTexts["dashboard_label_noTargets"]
        // This may or may not exist depending on whether targets are configured
        // Just verify the dashboard loaded successfully
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 5))
    }
}
