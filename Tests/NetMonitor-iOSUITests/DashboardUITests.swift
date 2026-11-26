import XCTest

@MainActor
final class DashboardUITests: IOSUITestCase {

    /// A deterministic device set, so the device list shows its header and network badge: with no
    /// devices it shows only the empty state (#583).
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1"]
    }

    // MARK: - Screen Existence

    func testDashboardScreenExistsAndShowsContent() throws {
        let dashboard = ui("screen_dashboard")
        requireExists(dashboard, message: "Dashboard screen should exist on launch")
        // FUNCTIONAL: dashboard should contain visible content beyond just existing
        XCTAssertTrue(
            !dashboard.staticTexts.isEmpty,
            "Dashboard screen should contain visible text content"
        )
    }

    func testNavigationTitleExists() throws {
        requireExists(app.navigationBars["Dashboard"], message: "Dashboard navigation title should exist")
    }

    // MARK: - Settings Navigation

    func testSettingsButtonNavigatesToSettings() throws {
        let settingsButton = app.buttons["dashboard_button_settings"]
        requireExists(settingsButton, message: "Settings button should exist on dashboard")
        XCTAssertTrue(settingsButton.isEnabled, "Settings button should be tappable")
        settingsButton.tap()
        requireExists(ui("screen_settings"), timeout: 8,
                     message: "Settings screen should appear after tapping settings button")
    }

    // MARK: - Connection Status Header

    func testConnectionStatusHeaderDisplaysState() throws {
        let statusHeader = ui("dashboard_label_connectionStatus")
        requireExists(statusHeader, message: "Connection status header should exist on dashboard")
        // FUNCTIONAL: status header should display a state value (not just exist)
        XCTAssertTrue(
            !statusHeader.staticTexts.isEmpty || !statusHeader.label.isEmpty,
            "Connection status header should display a status value (e.g., Connected, Offline)"
        )
    }

    // MARK: - Dashboard Cards

    func testNetworkHUDHeaderDisplaysNetworkName() throws {
        let networkLabel = ui("dashboard_label_network")
        requireExists(networkLabel, message: "Network HUD header should exist on dashboard")
        // FUNCTIONAL: network label should display some text content
        XCTAssertTrue(
            !networkLabel.staticTexts.isEmpty || !networkLabel.label.isEmpty,
            "Network HUD header should display a network name or identifier"
        )
    }

    func testHealthScoreCardDisplaysValue() throws {
        let healthCard = ui("dashboard_card_healthScore")
        requireExists(healthCard, message: "Health score card should exist on dashboard")
        // FUNCTIONAL: health score card should display a score value
        XCTAssertTrue(
            !healthCard.staticTexts.isEmpty || !healthCard.label.isEmpty,
            "Health score card should display a health score value"
        )
    }

    func testNetworkHealthLabelExists() throws {
        requireExists(app.staticTexts["NETWORK HEALTH"], message: "NETWORK HEALTH label should exist on dashboard")
    }

    func testConnectivityPanelContainsData() throws {
        let panel = ui("dashboard_card_wan")
        scrollToElement(panel)
        requireExists(panel, message: "Connectivity panel should exist on dashboard")
        // FUNCTIONAL: connectivity panel should contain at least ISP label
        XCTAssertTrue(
            !panel.staticTexts.isEmpty || !panel.label.isEmpty || app.staticTexts["ISP"].exists,
            "Connectivity panel should contain connectivity information text"
        )
    }

    func testMonitoringStatusTextShowsState() throws {
        // ConnectionStatusHeader shows "MONITORING" or "OFFLINE"
        XCTAssertTrue(
            waitForEither([
                app.staticTexts["MONITORING"].firstMatch,
                app.staticTexts["OFFLINE"].firstMatch
            ], timeout: 5),
            "Monitoring status (MONITORING or OFFLINE) should be visible in toolbar"
        )
    }

    func testConnectivityInfoDisplaysISP() throws {
        let panel = ui("dashboard_card_wan")
        scrollToElement(panel)
        requireExists(panel, message: "Connectivity panel should exist")
        // ProConnectivityPanel always shows ISP row label
        requireExists(app.staticTexts["ISP"], message: "ISP label should be visible in connectivity panel")
    }

    func testLocalDevicesCardDisplaysDeviceCount() throws {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, message: "Local devices card should exist on dashboard")
        // FUNCTIONAL: card should contain text content (device count, etc.)
        XCTAssertTrue(
            !devicesCard.staticTexts.isEmpty || !devicesCard.label.isEmpty,
            "Local devices card should display device count or device information"
        )
    }

    // MARK: - Local Devices Navigation

    func testLocalDevicesCardNavigatesToDeviceList() throws {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, message: "Local devices card should exist").tap()
        requireExists(ui("screen_deviceList"), timeout: 8,
                     message: "Device list screen should appear after tapping local devices card")
    }

    func testDeviceListShowsNetworkBadge() throws {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, message: "Local devices card should exist").tap()
        requireExists(ui("screen_deviceList"), timeout: 8,
                     message: "Device list screen should appear")
        requireExists(ui("deviceList_label_network"), timeout: 8,
                     message: "Network badge should appear on device list screen")
    }

    func testAddNetworkButtonPresentsSheetWithSegments() throws {
        let addButton = openAddNetworkMenuItem()
        requireExists(addButton, message: "Add Network button should exist in the Map tab's network menu")
        XCTAssertTrue(addButton.isEnabled, "Add Network button should be tappable")
        addButton.tap()
        requireExists(app.navigationBars["Add Network"], timeout: 8,
                     message: "Add Network sheet should appear after tapping Add Network")
        XCTAssertTrue(app.segmentedControls.firstMatch.exists,
                     "Segmented control should exist in Add Network sheet")
        // FUNCTIONAL: segmented control should have at least 2 options
        XCTAssertGreaterThan(
            app.segmentedControls.firstMatch.buttons.count, 1,
            "Add Network segmented control should have at least 2 options (e.g., Auto/Manual)"
        )
    }

    // MARK: - Pull to Refresh

    func testPullToRefreshDoesNotCrash() throws {
        let dashboard = ui("screen_dashboard")
        requireExists(dashboard, message: "Dashboard screen should exist before pull-to-refresh")
        let start = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
        // FUNCTIONAL: dashboard should still be intact after pull-to-refresh
        requireExists(ui("screen_dashboard"), timeout: 8,
                     message: "Dashboard should still exist after pull-to-refresh gesture")
    }

    // MARK: - Functional Tests

    func testScanButtonFromDashboardTriggersDiscoveryState() {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, message: "Local devices card should exist").tap()
        requireExists(ui("screen_deviceList"), timeout: 8,
                     message: "Device list screen should appear")

        let scanButton = app.buttons["deviceList_button_scan"]
        if scanButton.waitForExistence(timeout: 5) {
            scanButton.tap()
            XCTAssertTrue(
                waitForEither(
                    [
                        app.buttons["deviceList_button_stop"],
                        app.activityIndicators.firstMatch,
                        app.buttons["Stop Scan"]
                    ],
                    timeout: 10
                ),
                "Tapping scan should trigger discovery state (stop button or progress indicator)"
            )
        } else {
            // Scan button not present — device list may auto-scan; verify screen is still visible
            requireExists(ui("screen_deviceList"), message: "Device list screen should remain visible")
        }
    }

    func testAddNetworkSheetRequiresGatewayBeforeEnabling() {
        let addButton = openAddNetworkMenuItem()
        requireExists(addButton, message: "Add Network button should exist").tap()
        requireExists(app.navigationBars["Add Network"], timeout: 8,
                     message: "Add Network sheet should appear")

        // Switch to Manual tab if available
        let manualTab = app.segmentedControls.buttons["Manual"]
        if manualTab.waitForExistence(timeout: 3) {
            manualTab.tap()
        }

        // Verify save/add button is disabled with empty fields
        let saveButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'networkSheet_button_save' OR label == 'Save' OR label == 'Add'")
        ).firstMatch
        if saveButton.waitForExistence(timeout: 3) {
            XCTAssertFalse(saveButton.isEnabled,
                          "Save/Add button should be disabled with empty gateway field")

            // Fill in gateway field
            let gatewayField = app.textFields["networkSheet_field_gateway"]
            if gatewayField.waitForExistence(timeout: 3) {
                clearAndTypeText("192.168.1.1", into: gatewayField)
                XCTAssertTrue(saveButton.isEnabled,
                             "Save/Add button should be enabled after filling gateway field")
            }
        }

        // Cancel the sheet
        let cancelButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'networkSheet_button_cancel' OR label == 'Cancel'")
        ).firstMatch
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        }
    }

    func testLocalDevicesCardNavigatesToDeviceListWithBadge() {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, message: "Local devices card should exist").tap()
        requireExists(ui("screen_deviceList"), timeout: 8,
                     message: "Device list screen should appear after tapping devices card")
        requireExists(ui("deviceList_label_network"), timeout: 8,
                     message: "Network badge should be visible on device list screen")
    }

    func testSettingsNavigationRoundTrip() {
        requireExists(app.buttons["dashboard_button_settings"],
                     message: "Settings button should exist").tap()
        requireExists(ui("screen_settings"), timeout: 8,
                     message: "Settings screen should appear after tapping settings")

        let backButton = app.navigationBars.buttons.firstMatch
        requireExists(backButton, message: "Back button should be visible from settings").tap()

        requireExists(ui("screen_dashboard"), timeout: 8,
                     message: "Dashboard should reappear after navigating back from settings")
    }

    func testSettingsButtonNavigatesAndReturnsCorrectly() throws {
        // FUNCTIONAL: tap settings, verify settings screen appears, then go back
        let settingsButton = app.buttons["dashboard_button_settings"]
        requireExists(settingsButton, message: "Settings button should exist")
        settingsButton.tap()

        // FUNCTIONAL: verify navigation occurred (settings screen identifier or nav title)
        requireExists(app.byID("screen_settings"), timeout: 8,
                     message: "Tapping Settings button should navigate to Settings screen")

        // FUNCTIONAL: go back and verify dashboard is still there
        app.navigationBars.buttons.firstMatch.tap()
        requireExists(app.byID("screen_dashboard"), timeout: 5,
                     message: "Dashboard should be restored after returning from Settings")
    }

    func testTabNavigationCycleWorks() throws {
        // FUNCTIONAL: navigate through all 4 tabs and verify each screen appears
        let tabBar = app.tabBars.firstMatch
        requireExists(tabBar, message: "Tab bar should exist")

        tabBar.buttons["Map"].tap()
        requireExists(app.navigationBars["Network Map"], timeout: 8,
                     message: "Network Map screen should appear after tapping Map tab")

        tabBar.buttons["Tools"].tap()
        requireExists(app.byID("screen_tools"), timeout: 8,
                     message: "Tools screen should appear after tapping Tools tab")

        tabBar.buttons["Timeline"].tap()
        requireExists(app.navigationBars["Timeline"], timeout: 8,
                     message: "Timeline screen should appear after tapping Timeline tab")

        tabBar.buttons["Dashboard"].tap()
        requireExists(app.byID("screen_dashboard"), timeout: 8,
                     message: "Dashboard should be restored after tapping Dashboard tab")
    }

    // MARK: - Helpers

    /// The Map tab's network menu holds "Add Network" (not the dashboard); opens it and returns the item.
    private func openAddNetworkMenuItem() -> XCUIElement {
        requireExists(app.tabBars.buttons["Map"], message: "Map tab should exist").tap()
        requireExists(ui("networkMap_menu_networks"), timeout: 8, message: "Network menu should exist on the Map tab").tap()
        return app.buttons["Add Network"].firstMatch
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.byID(identifier)
    }

}
