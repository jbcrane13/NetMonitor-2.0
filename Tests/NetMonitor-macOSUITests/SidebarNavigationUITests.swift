import XCTest

@MainActor
final class SidebarNavigationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["XCUITEST"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "App main window should appear after launch")
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Sidebar Existence (upgraded: tap + verify content loads)

    func testSidebarNavigationExists() {
        let sidebar = app.outlines["sidebar_navigation"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5),
                      "Sidebar navigation list should exist")
        // Verify the sidebar is interactive — it should contain selectable rows
        let hasRows = sidebar.outlineRows.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasRows,
                      "Sidebar should contain at least one selectable outline row")
    }

    func testSidebarHasDashboardItem() {
        let item = app.descendants(matching: .any)["sidebar_dashboard"]
        XCTAssertTrue(item.waitForExistence(timeout: 5),
                      "Dashboard sidebar item should exist")
        // Tap and verify dashboard content actually loads
        item.tap()
        let detail = app.otherElements["detail_dashboard"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "Dashboard detail pane should appear after tapping sidebar item")
    }

    func testSidebarHasTargetsItem() {
        let item = app.descendants(matching: .any)["sidebar_targets"]
        XCTAssertTrue(item.waitForExistence(timeout: 5),
                      "Targets sidebar item should exist")
        // Tap and verify targets content actually loads
        item.tap()
        let detail = app.otherElements["detail_targets"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "Targets detail pane should appear after tapping sidebar item")
        // Verify targets view has functional content
        let hasContent = app.buttons["targets_button_add"].waitForExistence(timeout: 3)
            || app.tables.firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(hasContent,
                      "Targets pane should show add button or table after navigation")
    }

    func testSidebarHasDevicesItem() {
        let item = app.descendants(matching: .any)["sidebar_nav_devices"]
        XCTAssertTrue(item.waitForExistence(timeout: 5),
                      "Devices sidebar item should exist")
        // Tap and verify devices content actually loads
        item.tap()
        let detail = app.otherElements["detail_devices"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "Devices detail pane should appear after tapping sidebar item")
    }

    func testSidebarHasToolsItem() {
        let item = app.descendants(matching: .any)["sidebar_nav_tools"]
        XCTAssertTrue(item.waitForExistence(timeout: 5),
                      "Tools sidebar item should exist")
        // Tap and verify tools content actually loads with tool cards
        item.tap()
        let detail = app.otherElements["detail_tools"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "Tools detail pane should appear after tapping sidebar item")
        // Verify at least one tool card is visible
        let hasToolCard = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'tools_card_'")
        ).firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasToolCard,
                      "Tools pane should show at least one tool card after navigation")
    }

    func testSidebarHasSettingsItem() {
        let item = app.descendants(matching: .any)["sidebar_nav_settings"]
        XCTAssertTrue(item.waitForExistence(timeout: 5),
                      "Settings sidebar item should exist")
        // Tap and verify settings content actually loads with tabs
        item.tap()
        let detail = app.otherElements["detail_settings"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "Settings detail pane should appear after tapping sidebar item")
        // Verify settings has tab content
        let hasTabs = app.staticTexts["settings_tab_general"].waitForExistence(timeout: 3)
        XCTAssertTrue(hasTabs,
                      "Settings pane should show tab controls after navigation")
    }

    // MARK: - Navigation (upgraded: verify content changes, not just detail pane exists)

    func testSelectDashboardShowsDetailPane() {
        let sidebar = app.descendants(matching: .any)["sidebar_dashboard"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 3))

        // Verify dashboard content is populated (not just container exists)
        let hasDashboardContent = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard_'")
        ).firstMatch.waitForExistence(timeout: 5)
            || app.otherElements.matching(
                NSPredicate(format: "identifier BEGINSWITH 'networkDetail_'")
            ).firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasDashboardContent,
                      "Dashboard detail should have visible content after navigation")
    }

    func testSelectTargetsShowsDetailPane() {
        let sidebar = app.descendants(matching: .any)["sidebar_targets"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_targets"].waitForExistence(timeout: 3))

        // Verify targets content is populated
        let hasTargetsContent = app.buttons["targets_button_add"].waitForExistence(timeout: 5)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Target'")
            ).firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasTargetsContent,
                      "Targets detail should have functional content after navigation")
    }

    func testSelectDevicesShowsDetailPane() {
        let sidebar = app.descendants(matching: .any)["sidebar_nav_devices"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_devices"].waitForExistence(timeout: 3))

        // Verify devices content is populated (scan button, device list, or empty state)
        let hasDevicesContent = app.buttons.matching(
            NSPredicate(format: "identifier CONTAINS 'scan' OR identifier CONTAINS 'devices'")
        ).firstMatch.waitForExistence(timeout: 5)
            || app.staticTexts.matching(
                NSPredicate(format: "identifier BEGINSWITH 'devices_'")
            ).firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasDevicesContent,
                      "Devices detail should have functional content after navigation")
    }

    func testSelectToolsShowsDetailPane() {
        let sidebar = app.descendants(matching: .any)["sidebar_nav_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_tools"].waitForExistence(timeout: 3))

        // Verify tools content is populated with tool cards
        let hasToolCards = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'tools_card_'")
        ).firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasToolCards,
                      "Tools detail should show tool cards after navigation")
    }

    func testSelectSettingsShowsDetailPane() {
        let sidebar = app.descendants(matching: .any)["sidebar_nav_settings"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertTrue(app.otherElements["detail_settings"].waitForExistence(timeout: 3))

        // Verify settings content is populated with tab controls
        let hasSettingsContent = app.staticTexts["settings_tab_general"].waitForExistence(timeout: 5)
        XCTAssertTrue(hasSettingsContent,
                      "Settings detail should show tab controls after navigation")
    }

    // MARK: - Navigation Switching (upgraded: verify content changes between sections)

    func testSwitchBetweenSections() {
        // Start at dashboard
        let dashboard = app.descendants(matching: .any)["sidebar_dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        dashboard.tap()
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 3))

        // Switch to tools — dashboard detail should disappear
        app.descendants(matching: .any)["sidebar_nav_tools"].tap()
        XCTAssertTrue(app.otherElements["detail_tools"].waitForExistence(timeout: 3))
        let dashboardGone = !app.otherElements["detail_dashboard"].exists
        XCTAssertTrue(dashboardGone,
                      "Dashboard detail should not be visible after switching to Tools")

        // Switch to settings — tools detail should disappear
        app.descendants(matching: .any)["sidebar_nav_settings"].tap()
        XCTAssertTrue(app.otherElements["detail_settings"].waitForExistence(timeout: 3))
        let toolsGone = !app.otherElements["detail_tools"].exists
        XCTAssertTrue(toolsGone,
                      "Tools detail should not be visible after switching to Settings")

        // Switch back to dashboard — settings detail should disappear
        dashboard.tap()
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 3))
        let settingsGone = !app.otherElements["detail_settings"].exists
        XCTAssertTrue(settingsGone,
                      "Settings detail should not be visible after switching to Dashboard")
    }

    func testDefaultSelectionIsDashboard() {
        // Dashboard should be selected by default on launch
        XCTAssertTrue(app.otherElements["detail_dashboard"].waitForExistence(timeout: 5))

        // Verify the default detail has actual content, not just an empty container
        let hasDefaultContent = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard_'")
        ).firstMatch.waitForExistence(timeout: 5)
            || app.otherElements.matching(
                NSPredicate(format: "identifier BEGINSWITH 'networkDetail_'")
            ).firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasDefaultContent,
                      "Default dashboard selection should have visible content on launch")
    }
}
