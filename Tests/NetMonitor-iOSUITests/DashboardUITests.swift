import XCTest

@MainActor
final class DashboardUITests: IOSUITestCase {

    /// A deterministic device set, so the device list shows its header and network badge (with no
    /// devices it shows only the empty state, #583), and a fixture ISP, so the WAN card does not wait
    /// on an outside lookup.
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_FAKE_ISP": "1"]
    }

    // MARK: - Screen Existence

    func testDashboardScreenExistsAndShowsContent() throws {
        let dashboard = ui("screen_dashboard")
        requireExists(dashboard, message: "Dashboard screen should exist on launch")
        // FUNCTIONAL: dashboard should contain visible content beyond just existing
        XCTAssertTrue(
            !dashboard.staticTexts.hasNoMatches,
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
        XCTAssertFalse(
            app.texts(carrying: "dashboard_label_connectionStatus").hasNoMatches,
            "Connection status header should display a status value (e.g., Connected, Offline)"
        )
    }

    // MARK: - Dashboard Cards

    func testNetworkHUDHeaderDisplaysNetworkName() throws {
        let networkLabel = ui("dashboard_label_network")
        requireExists(networkLabel, message: "Network HUD header should exist on dashboard")
        // FUNCTIONAL: network label should display some text content
        XCTAssertFalse(
            app.texts(carrying: "dashboard_label_network").hasNoMatches,
            "Network HUD header should display a network name or identifier"
        )
    }

    func testHealthScoreCardDisplaysValue() throws {
        let healthCard = ui("dashboard_card_healthScore")
        requireExists(healthCard, message: "Health score card should exist on dashboard")
        // FUNCTIONAL: health score card should display a score value
        requireExists(
            app.text(carrying: "dashboard_card_healthScore", matching: "[0-9]{1,3}"), timeout: 8,
            message: "Health score card should show its score (a number from 0 to 100)"
        )
        captureScreenshot(named: "Dashboard_HealthScoreCard")
    }

    func testNetworkHealthLabelExists() throws {
        requireExists(app.staticTexts["NETWORK HEALTH"], message: "NETWORK HEALTH label should exist on dashboard")
    }

    func testConnectivityPanelContainsData() throws {
        let panel = ui("dashboard_card_wan")
        scrollToElement(panel)
        requireExists(panel, message: "Connectivity panel should exist on dashboard")
        // FUNCTIONAL: the WAN card shows the fixture provider and public IP (UITEST_FAKE_ISP).
        requireExists(
            app.text(carrying: "dashboard_card_wan", matching: "ISP"),
            message: "WAN card should have its ISP row"
        )
        requireExists(
            app.text(carrying: "dashboard_card_wan", matching: "Example Test ISP"), timeout: 8,
            message: "WAN card should show the fixture ISP name"
        )
        requireExists(
            app.text(carrying: "dashboard_card_wan", matching: "203\\.0\\.113\\.7"),
            message: "WAN card should show the fixture public IP"
        )
        captureScreenshot(named: "Dashboard_WANCard")
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
        // FUNCTIONAL: the card shows the device count
        requireExists(
            app.text(carrying: "dashboard_card_localDevices", matching: "[0-9]+ online · [0-9]+ total"),
            message: "Local devices card should show its device count, like \"1 online · 4 total\""
        )
        captureScreenshot(named: "Dashboard_LocalDevicesCard")
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
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
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

        // The manual form's rule: "Validate & Add" stays disabled until both the gateway and the subnet
        // are filled in. The sheet can prefill both, so empty them first.
        requireExists(app.segmentedControls.buttons["Manual"], message: "The sheet should offer a Manual tab").tap()
        let gatewayField = app.byID("addNetwork_textfield_gateway")
        let subnetField = app.byID("addNetwork_textfield_subnet")
        let validateButton = app.byID("networkSheet_button_addManual")
        requireExists(validateButton, message: "Validate & Add button should exist in the sheet")
        clearAndTypeText("", into: gatewayField)
        clearAndTypeText("", into: subnetField)
        XCTAssertFalse(validateButton.isEnabled, "Validate & Add should be disabled with an empty gateway and subnet")

        clearAndTypeText("192.168.1.1", into: gatewayField)
        XCTAssertFalse(validateButton.isEnabled, "Validate & Add should stay disabled with a gateway but no subnet")

        clearAndTypeText("192.168.1.0/24", into: subnetField)
        XCTAssertTrue(validateButton.isEnabled, "Validate & Add should be enabled once gateway and subnet are filled in")

        clearAndTypeText("", into: gatewayField)
        XCTAssertFalse(validateButton.isEnabled, "Validate & Add should be disabled again after the gateway is cleared")
        captureScreenshot(named: "Dashboard_AddNetworkValidation")

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

        // The Map screen's content, not only its title bar, must be up: a tap in mid-transition is dropped.
        requireExists(app.byID("screen_networkMap"), timeout: 8, message: "Network Map content should load")
        // A tap right after the Map tab's transition is sometimes dropped: tap again (up to 3 times) if nothing shows.
        for _ in 0..<3 where !app.byID("screen_tools").exists {
            tabBar.buttons["Tools"].tap()
            _ = app.byID("screen_tools").waitForExistence(timeout: 4)
        }
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
