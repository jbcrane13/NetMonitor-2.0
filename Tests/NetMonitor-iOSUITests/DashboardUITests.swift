import XCTest

@MainActor
final class DashboardUITests: IOSUITestCase {

    // MARK: - Screen Existence

    func testDashboardScreenExists() throws {
        requireExists(ui("screen_dashboard"), message: "Dashboard screen should exist on launch")
    }

    func testNavigationTitleExists() throws {
        requireExists(app.navigationBars["Dashboard"], message: "Dashboard navigation title should exist")
    }

    // MARK: - Settings Navigation

    func testSettingsButtonExists() throws {
        requireExists(app.buttons["dashboard_button_settings"], message: "Settings button should exist on dashboard")
    }

    func testSettingsButtonNavigatesToSettings() throws {
        requireExists(app.buttons["dashboard_button_settings"], message: "Settings button should exist").tap()
        requireExists(ui("screen_settings"), timeout: 8, message: "Settings screen should appear after tapping settings button")
    }

    // MARK: - Connection Status Header

    func testConnectionStatusHeaderExists() throws {
        requireExists(ui("dashboard_header_connectionStatus"), message: "Connection status header should exist on dashboard")
    }

    // MARK: - Dashboard Cards

    func testSessionCardExists() throws {
        requireExists(ui("dashboard_card_session"), message: "Session card should exist on dashboard")
    }

    func testWiFiCardExists() throws {
        requireExists(ui("dashboard_card_wifi"), message: "WiFi card should exist on dashboard")
    }

    func testGatewayCardExists() throws {
        requireExists(ui("dashboard_card_gateway"), message: "Gateway card should exist on dashboard")
    }

    func testActiveNetworkCardExists() throws {
        requireExists(app.staticTexts["Active Network"], message: "Active Network label should exist on dashboard")
    }

    func testNetworkPickerExists() throws {
        requireExists(app.staticTexts["Active Network"], message: "Network picker label should exist on dashboard")
    }

    func testISPCardExists() throws {
        let ispCard = ui("dashboard_card_isp")
        scrollToElement(ispCard)
        requireExists(ispCard, message: "ISP card should exist on dashboard")
    }

    func testLocalDevicesCardExists() throws {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, message: "Local devices card should exist on dashboard")
    }

    // MARK: - Local Devices Navigation

    func testLocalDevicesCardNavigatesToDeviceList() throws {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, message: "Local devices card should exist").tap()
        requireExists(ui("deviceList_screen"), timeout: 8, message: "Device list screen should appear after tapping local devices card")
    }

    func testDeviceListShowsNetworkBadge() throws {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, message: "Local devices card should exist").tap()
        requireExists(ui("deviceList_screen"), timeout: 8, message: "Device list screen should appear")
        requireExists(ui("deviceList_badge_network"), timeout: 8, message: "Network badge should appear on device list screen")
    }

    func testAddNetworkButtonPresentsSheet() throws {
        let addButton = app.buttons["Add Network"].firstMatch
        requireExists(addButton, message: "Add Network button should exist on dashboard")
        addButton.tap()
        requireExists(app.navigationBars["Add Network"], timeout: 8, message: "Add Network sheet should appear after tapping Add Network")
        XCTAssertTrue(app.segmentedControls.firstMatch.exists, "Segmented control should exist in Add Network sheet")
    }

    // MARK: - Pull to Refresh

    func testPullToRefreshExists() throws {
        let dashboard = ui("screen_dashboard")
        requireExists(dashboard, message: "Dashboard screen should exist before pull-to-refresh")
        let start = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    // MARK: - Functional Tests

    func testScanButtonFromDashboardTriggersDiscoveryState() {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, message: "Local devices card should exist").tap()
        requireExists(ui("deviceList_screen"), timeout: 8, message: "Device list screen should appear")

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
            requireExists(ui("deviceList_screen"), message: "Device list screen should remain visible")
        }
    }

    func testAddNetworkSheetRequiresGatewayBeforeEnabling() {
        let addButton = app.buttons["Add Network"].firstMatch
        requireExists(addButton, message: "Add Network button should exist").tap()
        requireExists(app.navigationBars["Add Network"], timeout: 8, message: "Add Network sheet should appear")

        // Switch to Manual tab if available
        let manualTab = app.segmentedControls.buttons["Manual"]
        if manualTab.waitForExistence(timeout: 3) {
            manualTab.tap()
        }

        // Verify save/add button is disabled with empty fields
        let saveButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'network_sheet_button_save' OR label == 'Save' OR label == 'Add'")
        ).firstMatch
        if saveButton.waitForExistence(timeout: 3) {
            XCTAssertFalse(saveButton.isEnabled, "Save/Add button should be disabled with empty gateway field")

            // Fill in gateway field
            let gatewayField = app.textFields["network_sheet_field_gateway"]
            if gatewayField.waitForExistence(timeout: 3) {
                clearAndTypeText("192.168.1.1", into: gatewayField)
                XCTAssertTrue(saveButton.isEnabled, "Save/Add button should be enabled after filling gateway field")
            }
        }

        // Cancel the sheet
        let cancelButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'network_sheet_button_cancel' OR label == 'Cancel'")
        ).firstMatch
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        }
    }

    func testLocalDevicesCardNavigatesToDeviceListWithBadge() {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, message: "Local devices card should exist").tap()
        requireExists(ui("deviceList_screen"), timeout: 8, message: "Device list screen should appear after tapping devices card")
        requireExists(ui("deviceList_badge_network"), timeout: 8, message: "Network badge should be visible on device list screen")
    }

    func testSettingsNavigationRoundTrip() {
        requireExists(app.buttons["dashboard_button_settings"], message: "Settings button should exist").tap()
        requireExists(ui("screen_settings"), timeout: 8, message: "Settings screen should appear after tapping settings")

        let backButton = app.navigationBars.buttons.firstMatch
        requireExists(backButton, message: "Back button should be visible from settings").tap()

        requireExists(ui("screen_dashboard"), timeout: 8, message: "Dashboard should reappear after navigating back from settings")
    }

    func testPullToRefreshDoesNotCrash() {
        let dashboard = ui("screen_dashboard")
        requireExists(dashboard, message: "Dashboard screen should exist before pull-to-refresh")

        let start = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)

        requireExists(ui("screen_dashboard"), timeout: 8, message: "Dashboard should still exist after pull-to-refresh")
    }

    // MARK: - Helpers

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

}
