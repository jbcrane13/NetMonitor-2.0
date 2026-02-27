import XCTest

@MainActor
final class SidebarNavigationUITests: XCTestCase {
    var app: XCUIApplication!

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
        XCTAssertTrue(app.staticTexts["sidebar_dashboard"].waitForExistence(timeout: 5))
    }

    func testSidebarHasTargetsItem() {
        XCTAssertTrue(app.staticTexts["sidebar_targets"].waitForExistence(timeout: 5))
    }

    func testSidebarHasDevicesItem() {
        XCTAssertTrue(app.staticTexts["sidebar_devices"].waitForExistence(timeout: 5))
    }

    func testSidebarHasToolsItem() {
        XCTAssertTrue(app.staticTexts["sidebar_tools"].waitForExistence(timeout: 5))
    }

    func testSidebarHasSettingsItem() {
        XCTAssertTrue(app.staticTexts["sidebar_settings"].waitForExistence(timeout: 5))
    }

    // MARK: - Navigation

    func testSelectDashboardShowsDetailPane() {
        let sidebar = app.staticTexts["sidebar_dashboard"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 3))
    }

    func testSelectTargetsShowsDetailPane() {
        let sidebar = app.staticTexts["sidebar_targets"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_targets"].waitForExistence(timeout: 3))
    }

    func testSelectDevicesShowsDetailPane() {
        let sidebar = app.staticTexts["sidebar_devices"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_devices"].waitForExistence(timeout: 3))
    }

    func testSelectToolsShowsDetailPane() {
        let sidebar = app.staticTexts["sidebar_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_tools"].waitForExistence(timeout: 3))
    }

    func testSelectSettingsShowsDetailPane() {
        let sidebar = app.staticTexts["sidebar_settings"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_settings"].waitForExistence(timeout: 3))
    }

    // MARK: - Navigation Switching

    func testSwitchBetweenSections() {
        // Start at dashboard
        let dashboard = app.staticTexts["sidebar_dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        dashboard.tap()
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 3))

        // Switch to tools
        app.staticTexts["sidebar_tools"].tap()
        XCTAssertTrue(app.otherElements["detail_tools"].waitForExistence(timeout: 3))

        // Switch to settings
        app.staticTexts["sidebar_settings"].tap()
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
