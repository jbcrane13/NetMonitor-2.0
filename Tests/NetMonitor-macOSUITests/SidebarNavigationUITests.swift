import XCTest

@MainActor
final class SidebarNavigationUITests: MacOSUITestCase {

    /// The first network's sidebar row. Its dashboard replaced the Dashboard section
    /// (9704f2d0) and is what the app opens on (b8e467ae).
    private var networkRow: XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'sidebar_row_network'")
        ).firstMatch
    }

    /// Leave the launch dashboard, then come back to it through its sidebar row.
    private func reselectDashboard() {
        navigateToSidebar("tools")
        XCTAssertTrue(waitForDisappearance(ui("contentView_nav_network").firstMatch),
                      "Dashboard should leave the detail pane when Tools is selected")
        XCTAssertTrue(networkRow.waitForExistence(timeout: 5),
                      "Network sidebar row should exist")
        networkRow.click()
    }

    // MARK: - Sidebar Existence (upgraded: tap + verify content loads)

    func testSidebarNavigationExists() {
        // The list has no id of its own since d85ffc7d; find it by a row it holds.
        let sidebar = app.outlines.containing(.any, identifier: "sidebar_nav_tools").firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5),
                      "Sidebar navigation list should exist")
        // Verify the sidebar is interactive — it should contain selectable rows
        let hasRows = sidebar.outlineRows.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasRows,
                      "Sidebar should contain at least one selectable outline row")
    }

    func testSidebarHasDashboardItem() {
        // Select the network row and verify dashboard content actually loads
        reselectDashboard()
        let detail = ui("contentView_nav_network").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "Dashboard detail pane should appear after tapping sidebar item")
    }

    // Blocked on #546: the Targets section was removed in c82f8b17.
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
        let item = ui("sidebar_nav_devices").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5),
                      "Devices sidebar item should exist")
        // Tap and verify devices content actually loads
        item.click()
        let detail = ui("contentView_nav_devices").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "Devices detail pane should appear after tapping sidebar item")
    }

    func testSidebarHasToolsItem() {
        let item = ui("sidebar_nav_tools").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5),
                      "Tools sidebar item should exist")
        // Tap and verify tools content actually loads with tool cards
        item.click()
        let detail = ui("contentView_nav_tools").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "Tools detail pane should appear after tapping sidebar item")
        // Verify at least one tool card is visible
        let hasToolCard = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'tools_card_'")
        ).firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasToolCard,
                      "Tools pane should show at least one tool card after navigation")
    }

    func testSidebarHasSettingsItem() {
        let item = ui("sidebar_nav_settings").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5),
                      "Settings sidebar item should exist")
        // Tap and verify settings content actually loads with tabs
        item.click()
        let detail = ui("contentView_nav_settings").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5),
                      "Settings detail pane should appear after tapping sidebar item")
        // Verify settings has tab content
        let hasTabs = app.staticTexts["settings_tab_General"].waitForExistence(timeout: 3)
        XCTAssertTrue(hasTabs,
                      "Settings pane should show tab controls after navigation")
    }

    // MARK: - Navigation (upgraded: verify content changes, not just detail pane exists)

    func testSelectDashboardShowsDetailPane() {
        reselectDashboard()
        XCTAssertTrue(ui("contentView_nav_network").firstMatch.waitForExistence(timeout: 3))

        // Verify dashboard content is populated (not just container exists)
        let hasDashboardContent = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard_'")
        ).firstMatch.waitForExistence(timeout: 5)
            || app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'networkDetail_'")
            ).firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasDashboardContent,
                      "Dashboard detail should have visible content after navigation")
    }

    // Blocked on #546: the Targets section was removed in c82f8b17.
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
        let sidebar = ui("sidebar_nav_devices").firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.click()
        XCTAssertTrue(ui("contentView_nav_devices").firstMatch.waitForExistence(timeout: 3))

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
        let sidebar = ui("sidebar_nav_tools").firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.click()
        XCTAssertTrue(ui("contentView_nav_tools").firstMatch.waitForExistence(timeout: 3))

        // Verify tools content is populated with tool cards
        let hasToolCards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'tools_card_'")
        ).firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasToolCards,
                      "Tools detail should show tool cards after navigation")
    }

    func testSelectSettingsShowsDetailPane() {
        let sidebar = ui("sidebar_nav_settings").firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.click()
        XCTAssertTrue(ui("contentView_nav_settings").firstMatch.waitForExistence(timeout: 3))

        // Verify settings content is populated with tab controls
        let hasSettingsContent = app.staticTexts["settings_tab_General"].waitForExistence(timeout: 5)
        XCTAssertTrue(hasSettingsContent,
                      "Settings detail should show tab controls after navigation")
    }

    // MARK: - Navigation Switching (upgraded: verify content changes between sections)

    func testSwitchBetweenSections() {
        // Start at dashboard
        let dashboard = networkRow
        reselectDashboard()
        XCTAssertTrue(ui("contentView_nav_network").firstMatch.waitForExistence(timeout: 3))

        // Switch to tools — dashboard detail should disappear
        ui("sidebar_nav_tools").firstMatch.click()
        XCTAssertTrue(ui("contentView_nav_tools").firstMatch.waitForExistence(timeout: 3))
        let dashboardGone = !ui("contentView_nav_network").firstMatch.exists
        XCTAssertTrue(dashboardGone,
                      "Dashboard detail should not be visible after switching to Tools")

        // Switch to settings — tools detail should disappear
        ui("sidebar_nav_settings").firstMatch.click()
        XCTAssertTrue(ui("contentView_nav_settings").firstMatch.waitForExistence(timeout: 3))
        let toolsGone = !ui("contentView_nav_tools").firstMatch.exists
        XCTAssertTrue(toolsGone,
                      "Tools detail should not be visible after switching to Settings")

        // Switch back to dashboard — settings detail should disappear
        dashboard.click()
        XCTAssertTrue(ui("contentView_nav_network").firstMatch.waitForExistence(timeout: 3))
        let settingsGone = !ui("contentView_nav_settings").firstMatch.exists
        XCTAssertTrue(settingsGone,
                      "Settings detail should not be visible after switching to Dashboard")
    }

    func testDefaultSelectionIsDashboard() {
        // Dashboard should be selected by default on launch
        XCTAssertTrue(ui("contentView_nav_network").firstMatch.waitForExistence(timeout: 5))

        // Verify the default detail has actual content, not just an empty container
        let hasDefaultContent = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'dashboard_'")
        ).firstMatch.waitForExistence(timeout: 5)
            || app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'networkDetail_'")
            ).firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(hasDefaultContent,
                      "Default dashboard selection should have visible content on launch")
    }
}
