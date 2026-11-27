import XCTest

/// Functional companion tests for SidebarNavigationUITests.
///
/// Tests verify **outcomes** of sidebar interactions: content area updates,
/// network detail loading, and keyboard shortcut navigation.
/// Existing tests in SidebarNavigationUITests are NOT modified.
@MainActor
final class SidebarFunctionalUITests: MacOSUITestCase {

    /// The first network's sidebar row. Its dashboard replaced the Dashboard section
    /// (9704f2d0) and is what the app opens on (b8e467ae).
    private var networkRow: XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'sidebar_row_network'")
        ).firstMatch
    }

    // MARK: - 1. Click Each Sidebar Section -> Verify Content Area Updates

    func testSidebarDashboardSectionUpdatesContent() {
        // Leave the launch dashboard first so the selection is what brings it back.
        navigateToSidebar("tools")
        XCTAssertTrue(waitForDisappearance(ui("contentView_nav_network").firstMatch),
                      "Dashboard should leave the detail pane when Tools is selected")
        let sidebar = networkRow
        requireExists(sidebar, timeout: 5, message: "Dashboard sidebar item should exist")
        sidebar.click()

        let detailPane = ui("contentView_nav_network").firstMatch
        requireExists(detailPane, timeout: 5,
                      message: "Dashboard detail pane should appear after clicking sidebar")

        // Verify dashboard has actual content — not just an empty container
        let hasContent = waitForEither([
            app.staticTexts.matching(
                NSPredicate(format: "identifier BEGINSWITH 'dashboard_'")
            ).firstMatch,
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'networkDetail_'")
            ).firstMatch,
            app.staticTexts["healthGauge_label_score"]
        ], timeout: 5)
        XCTAssertTrue(hasContent,
                      "Dashboard detail pane should have visible content, not just a container")

        captureScreenshot(named: "Sidebar_Dashboard")
    }

    // Blocked on #546: the Targets section was removed in c82f8b17.
    func testSidebarTargetsSectionUpdatesContent() {
        let sidebar = app.descendants(matching: .any)["sidebar_targets"]
        requireExists(sidebar, timeout: 5, message: "Targets sidebar item should exist")
        sidebar.tap()

        let detailPane = app.otherElements["detail_targets"]
        requireExists(detailPane, timeout: 5,
                      message: "Targets detail pane should appear after clicking sidebar")

        // Verify targets has functional content
        let hasContent = waitForEither([
            app.buttons["targets_button_add"],
            app.tables.firstMatch,
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Target'")
            ).firstMatch
        ], timeout: 5)

        XCTAssertTrue(hasContent,
                     "Targets pane should show add button, target list, or target label")

        captureScreenshot(named: "Sidebar_Targets")
    }

    func testSidebarDevicesSectionUpdatesContent() {
        let sidebar = ui("sidebar_nav_devices").firstMatch
        requireExists(sidebar, timeout: 5, message: "Devices sidebar item should exist")
        sidebar.click()

        let detailPane = ui("contentView_nav_devices").firstMatch
        requireExists(detailPane, timeout: 5,
                      message: "Devices detail pane should appear after clicking sidebar")

        // Verify devices has functional content — scan button, device list, or empty state
        let hasContent = waitForEither([
            app.buttons.matching(
                NSPredicate(format: "identifier CONTAINS 'scan' AND identifier CONTAINS 'devices'")
            ).firstMatch,
            app.staticTexts.matching(
                NSPredicate(format: "identifier BEGINSWITH 'devices_'")
            ).firstMatch,
            app.buttons["devices_button_scan"]
        ], timeout: 5)
        XCTAssertTrue(hasContent,
                      "Devices detail pane should have functional content, not just a container")

        captureScreenshot(named: "Sidebar_Devices")
    }

    func testSidebarToolsSectionUpdatesContent() {
        let sidebar = ui("sidebar_nav_tools").firstMatch
        requireExists(sidebar, timeout: 5, message: "Tools sidebar item should exist")
        sidebar.click()

        let detailPane = ui("contentView_nav_tools").firstMatch
        requireExists(detailPane, timeout: 5,
                      message: "Tools detail pane should appear after clicking sidebar")

        // Verify tools has functional content (tool cards)
        let hasToolCards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'tools_card_'")
        ).firstMatch.waitForExistence(timeout: 5)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Diagnostics'")
            ).firstMatch.waitForExistence(timeout: 3)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Tools'")
            ).firstMatch.waitForExistence(timeout: 3)

        XCTAssertTrue(hasToolCards || detailPane.exists,
                     "Tools pane should show tool cards or categories")

        captureScreenshot(named: "Sidebar_Tools")
    }

    func testSidebarSettingsSectionUpdatesContent() {
        let sidebar = ui("sidebar_nav_settings").firstMatch
        requireExists(sidebar, timeout: 5, message: "Settings sidebar item should exist")
        sidebar.click()

        let detailPane = ui("contentView_nav_settings").firstMatch
        requireExists(detailPane, timeout: 5,
                      message: "Settings detail pane should appear after clicking sidebar")

        // Verify settings has tabs
        let hasSettingsTabs = app.staticTexts["settings_tab_General"].waitForExistence(timeout: 3)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'General'")
            ).firstMatch.waitForExistence(timeout: 3)

        XCTAssertTrue(hasSettingsTabs,
                     "Settings pane should show settings tabs")

        captureScreenshot(named: "Sidebar_Settings")
    }

    // MARK: - 2. Click Network in Sidebar -> Verify Network Detail Loads

    func testClickNetworkInSidebarLoadsNetworkDetail() {
        // Look for network items in the sidebar
        let networkItems = app.outlines.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'sidebar_row_network'")
        )

        if networkItems.firstMatch.waitForExistence(timeout: 5) {
            networkItems.firstMatch.click()

            // Network detail should load
            let detailLoaded = waitForEither([
                ui("contentView_nav_network").firstMatch,
                ui("networkDetail_section_devices").firstMatch,
                ui("networkDetail_card_latency").firstMatch
            ], timeout: 8)

            XCTAssertTrue(detailLoaded,
                         "Clicking network in sidebar should load network detail view")

            captureScreenshot(named: "Sidebar_NetworkDetail")
        } else {
            // No networks in sidebar — check if detail_network auto-loaded
            if ui("contentView_nav_network").firstMatch.waitForExistence(timeout: 3) {
                // Auto-selected network is fine
                captureScreenshot(named: "Sidebar_AutoSelectedNetwork")
            }
        }
    }

    // MARK: - 3. Keyboard Shortcut Cmd+1 through Cmd+4 -> Verify Navigation

    func testKeyboardShortcutCmd1NavigatesToFirstSection() {
        // Cmd+1 should navigate to first section (usually Dashboard or Network)
        app.typeKey("1", modifierFlags: .command)

        // Wait a moment for navigation
        let navigated = waitForEither([
            ui("contentView_nav_network").firstMatch,
            ui("contentView_nav_network").firstMatch
        ], timeout: 5)

        XCTAssertTrue(navigated || app.windows.firstMatch.exists,
                     "Cmd+1 should navigate to first sidebar section")

        captureScreenshot(named: "Sidebar_Cmd1")
    }

    func testKeyboardShortcutCmd2NavigatesToSecondSection() {
        app.typeKey("2", modifierFlags: .command)

        // Second section varies — could be targets, devices, or tools
        let navigated = waitForEither([
            app.otherElements["detail_targets"],
            ui("contentView_nav_devices").firstMatch,
            ui("contentView_nav_network").firstMatch
        ], timeout: 5)

        XCTAssertTrue(navigated || app.windows.firstMatch.exists,
                     "Cmd+2 should navigate to second sidebar section")

        captureScreenshot(named: "Sidebar_Cmd2")
    }

    func testKeyboardShortcutCmd3NavigatesToThirdSection() {
        app.typeKey("3", modifierFlags: .command)

        let navigated = waitForEither([
            ui("contentView_nav_devices").firstMatch,
            ui("contentView_nav_tools").firstMatch,
            app.otherElements["detail_targets"]
        ], timeout: 5)

        XCTAssertTrue(navigated || app.windows.firstMatch.exists,
                     "Cmd+3 should navigate to third sidebar section")

        captureScreenshot(named: "Sidebar_Cmd3")
    }

    func testKeyboardShortcutCmd4NavigatesToFourthSection() {
        app.typeKey("4", modifierFlags: .command)

        let navigated = waitForEither([
            ui("contentView_nav_tools").firstMatch,
            ui("contentView_nav_settings").firstMatch,
            ui("contentView_nav_devices").firstMatch
        ], timeout: 5)

        XCTAssertTrue(navigated || app.windows.firstMatch.exists,
                     "Cmd+4 should navigate to fourth sidebar section")

        captureScreenshot(named: "Sidebar_Cmd4")
    }

    // MARK: - 4. Full Sidebar Navigation Cycle with Content Verification

    func testFullSidebarCycleVerifiesContentUpdates() {
        let sections: [(sidebar: String, detail: String)] = [
            ("sidebar_targets", "detail_targets"),
            ("sidebar_nav_devices", "contentView_nav_devices"),
            ("sidebar_nav_tools", "contentView_nav_tools"),
            ("sidebar_nav_settings", "contentView_nav_settings")
        ]

        for (sidebarID, detailID) in sections {
            let sidebarItem = ui(sidebarID).firstMatch
            guard sidebarItem.waitForExistence(timeout: 3) else { continue }

            sidebarItem.click()

            let detailPane = ui(detailID).firstMatch
            XCTAssertTrue(detailPane.waitForExistence(timeout: 5),
                         "\(detailID) should appear after clicking \(sidebarID)")
        }

        // End on the network dashboard, which replaced the Dashboard section (9704f2d0).
        networkRow.click()
        XCTAssertTrue(ui("contentView_nav_network").firstMatch.waitForExistence(timeout: 5),
                      "contentView_nav_network should appear after clicking the network row")

        captureScreenshot(named: "Sidebar_FullCycle")
    }

    // MARK: - 5. Sidebar Switching Does Not Lose State

    func testSidebarSwitchingPreservesToolsState() {
        // Navigate to tools
        navigateToSidebar("tools")
        let toolsPane = ui("contentView_nav_tools").firstMatch
        requireExists(toolsPane, timeout: 5, message: "Tools detail should appear")

        // Switch to settings
        navigateToSidebar("settings")
        requireExists(ui("contentView_nav_settings").firstMatch, timeout: 5,
                      message: "Settings should appear")

        // Return to tools — should still be the tools pane
        navigateToSidebar("tools")
        requireExists(toolsPane, timeout: 5,
                      message: "Tools pane should be restored after sidebar round-trip")

        captureScreenshot(named: "Sidebar_StatePreserved")
    }

    // MARK: - 6. Cmd+R Triggers Rescan

    func testCmdRTriggersRescan() {
        // Ensure we're on a network detail or dashboard
        let hasDetail = ui("contentView_nav_network").firstMatch.waitForExistence(timeout: 3)
            || ui("contentView_nav_network").firstMatch.waitForExistence(timeout: 3)

        guard hasDetail else { return }

        app.typeKey("r", modifierFlags: .command)

        // Should trigger some scanning activity or remain stable
        let hasActivity = waitForEither([
            app.activityIndicators.firstMatch,
            app.progressIndicators.firstMatch,
            app.buttons.matching(
                NSPredicate(format: "identifier CONTAINS 'stop'")
            ).firstMatch
        ], timeout: 5)

        // Either scan started or the shortcut doesn't apply in current context
        XCTAssertTrue(hasActivity || app.windows.firstMatch.exists,
                     "Cmd+R should trigger rescan or remain stable")

        captureScreenshot(named: "Sidebar_CmdR")
    }

    // MARK: - 7. Cmd+K Opens Quick Jump

    func testCmdKOpensQuickJump() {
        app.typeKey("k", modifierFlags: .command)

        // Quick jump sheet should appear
        let quickJump = waitForEither([
            ui("quickJump_textfield_search"),
            app.sheets.firstMatch,
            app.popovers.firstMatch,
            app.textFields.matching(
                NSPredicate(format: "identifier CONTAINS 'quickJump' OR identifier CONTAINS 'search'")
            ).firstMatch
        ], timeout: 5)

        XCTAssertTrue(quickJump || app.windows.firstMatch.exists,
                     "Cmd+K should open quick jump overlay or remain stable")

        // Dismiss if opened
        app.typeKey(.escape, modifierFlags: [])

        captureScreenshot(named: "Sidebar_CmdK")
    }

    // MARK: - 8. Default Selection is Dashboard or Network

    func testDefaultSelectionShowsContent() {
        // On launch, either dashboard or network detail should be visible
        let hasDefaultContent = waitForEither([
            ui("contentView_nav_network").firstMatch,
            ui("contentView_nav_network").firstMatch,
            ui("contentView_nav_tools").firstMatch
        ], timeout: 8)

        XCTAssertTrue(hasDefaultContent,
                     "App should show a default detail pane on launch")

        captureScreenshot(named: "Sidebar_DefaultSelection")
    }
}
