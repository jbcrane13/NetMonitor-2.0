@preconcurrency import XCTest

final class SidebarNavigationUITests: XCTestCase {
    nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Sidebar Existence

    func testSidebarNavigationExists() {
        XCTAssertTrue(app.outlines["sidebar_navigation"].waitForExistence(timeout: 5),
                      "Sidebar navigation list should exist")
    }

    func testSidebarHasDashboardItem() {
        XCTAssertTrue(app.descendants(matching: .any)["sidebar_dashboard"].waitForExistence(timeout: 5))
    }

    func testSidebarHasTargetsItem() {
        XCTAssertTrue(app.descendants(matching: .any)["sidebar_targets"].waitForExistence(timeout: 5))
    }

    func testSidebarHasDevicesItem() {
        XCTAssertTrue(app.descendants(matching: .any)["sidebar_nav_devices"].waitForExistence(timeout: 5))
    }

    func testSidebarHasToolsItem() {
        XCTAssertTrue(app.descendants(matching: .any)["sidebar_nav_tools"].waitForExistence(timeout: 5))
    }

    func testSidebarHasSettingsItem() {
        XCTAssertTrue(app.descendants(matching: .any)["sidebar_nav_settings"].waitForExistence(timeout: 5))
    }

    // MARK: - Navigation

    func testSelectDashboardShowsDetailPane() {
        let sidebar = app.descendants(matching: .any)["sidebar_dashboard"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 3))
    }

    func testSelectTargetsShowsDetailPane() {
        let sidebar = app.descendants(matching: .any)["sidebar_targets"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_targets"].waitForExistence(timeout: 3))
    }

    func testSelectDevicesShowsDetailPane() {
        let sidebar = app.descendants(matching: .any)["sidebar_nav_devices"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_devices"].waitForExistence(timeout: 3))
    }

    func testSelectToolsShowsDetailPane() {
        let sidebar = app.descendants(matching: .any)["sidebar_nav_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_tools"].waitForExistence(timeout: 3))
    }

    func testSelectSettingsShowsDetailPane() {
        let sidebar = app.descendants(matching: .any)["sidebar_nav_settings"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_settings"].waitForExistence(timeout: 3))
    }

    // MARK: - Navigation Switching

    func testSwitchBetweenSections() {
        // Start at dashboard
        let dashboard = app.descendants(matching: .any)["sidebar_dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        dashboard.tap()
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 3))

        // Switch to tools
        app.descendants(matching: .any)["sidebar_nav_tools"].tap()
        XCTAssertTrue(app.otherElements["detail_tools"].waitForExistence(timeout: 3))

        // Switch to settings
        app.descendants(matching: .any)["sidebar_nav_settings"].tap()
        XCTAssertTrue(app.otherElements["detail_settings"].waitForExistence(timeout: 3))

        // Switch back to dashboard
        dashboard.tap()
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 3))
    }

    func testDefaultSelectionIsDashboard() {
        // Dashboard should be selected by default on launch
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 5))
    }
}
