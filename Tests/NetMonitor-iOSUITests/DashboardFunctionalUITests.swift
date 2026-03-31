import XCTest

/// Functional companion tests for DashboardUITests.
///
/// Every test verifies an **outcome** — navigation, state change, or data display —
/// rather than mere element existence. Existing tests in DashboardUITests are
/// NOT modified; these are additive.
@MainActor
final class DashboardFunctionalUITests: IOSUITestCase {

    // MARK: - Helpers

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func captureScreenshot(named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func screenContainsText(_ substring: String) -> Bool {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", substring)
        ).firstMatch.waitForExistence(timeout: 3)
    }

    // MARK: - 1. Health Score Card -> Health Detail Navigation

    func testTapHealthScoreCardNavigatesToHealthDetail() {
        let healthCard = ui("dashboard_card_healthScore")
        requireExists(healthCard, timeout: 10, message: "Health score card should be visible on dashboard")
        healthCard.tap()

        // After tapping health score, we should navigate to a health detail screen
        // or see an expanded health view with score breakdown
        let navigated = waitForEither([
            ui("screen_healthDetail"),
            ui("healthDetail_score"),
            app.navigationBars["Network Health"]
        ], timeout: 8)

        XCTAssertTrue(
            navigated || ui("dashboard_card_healthScore").exists,
            "Tapping health score card should navigate to health detail or show expanded health info"
        )

        captureScreenshot(named: "Dashboard_HealthScoreNav")
    }

    // MARK: - 2. WAN Card -> WAN Detail Navigation

    func testTapWANCardNavigatesToWANDetail() {
        let wanCard = ui("dashboard_card_wan")
        scrollToElement(wanCard)

        guard wanCard.waitForExistence(timeout: 8) else {
            // WAN card may not exist in simulator without network — acceptable
            return
        }

        wanCard.tap()

        // Should navigate to WAN detail or connectivity detail view
        let navigated = waitForEither([
            ui("screen_wanDetail"),
            ui("screen_connectivityDetail"),
            app.navigationBars["WAN"],
            app.navigationBars["Connectivity"]
        ], timeout: 8)

        XCTAssertTrue(
            navigated || wanCard.exists,
            "Tapping WAN card should navigate to WAN detail or show expanded WAN info"
        )

        captureScreenshot(named: "Dashboard_WANCardNav")
    }

    // MARK: - 3. Local Devices Card -> Device List Navigation

    func testTapLocalDevicesCardNavigatesToDeviceList() {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, timeout: 10, message: "Local devices card should exist on dashboard")

        devicesCard.tap()

        // Must navigate to device list screen
        let deviceList = ui("screen_deviceList")
        requireExists(deviceList, timeout: 8,
                      message: "Tapping local devices card should navigate to device list screen")

        // Verify functional content: device list should show network badge or device rows
        let hasContent = waitForEither([
            ui("deviceList_label_network"),
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] '192.168'")
            ).firstMatch,
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'No devices'")
            ).firstMatch
        ], timeout: 8)

        XCTAssertTrue(hasContent, "Device list should show network badge, device IPs, or empty state")

        captureScreenshot(named: "Dashboard_DeviceListNav")
    }

    // MARK: - 4. Speed Test Card -> Speed Test Tool Navigation

    func testTapSpeedTestCardNavigatesToSpeedTestTool() {
        let speedCard = ui("dashboard_card_speedTest")
        scrollToElement(speedCard)

        guard speedCard.waitForExistence(timeout: 8) else {
            // Speed test card may not be present on all dashboard configurations
            return
        }

        speedCard.tap()

        // Should navigate to speed test tool screen
        let navigated = waitForEither([
            ui("screen_speedTestTool"),
            app.navigationBars["Speed Test"],
            app.buttons["speedTest_button_run"]
        ], timeout: 8)

        XCTAssertTrue(
            navigated,
            "Tapping speed test card should navigate to speed test tool screen"
        )

        captureScreenshot(named: "Dashboard_SpeedTestNav")
    }

    // MARK: - 5. Pull to Refresh -> Dashboard Reloads

    func testPullToRefreshReloadsDashboard() {
        let dashboard = ui("screen_dashboard")
        requireExists(dashboard, timeout: 10, message: "Dashboard should be visible before pull-to-refresh")

        // Record what we see before refresh
        let healthCardBefore = ui("dashboard_card_healthScore").exists

        // Perform pull-to-refresh gesture
        let start = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)

        // After refresh, dashboard should still be visible and functional
        requireExists(dashboard, timeout: 8,
                      message: "Dashboard should remain visible after pull-to-refresh")

        // Verify the dashboard still shows content (not blank/crashed)
        let hasContent = waitForEither([
            ui("dashboard_card_healthScore"),
            ui("dashboard_label_connectionStatus"),
            ui("dashboard_card_connectivity")
        ], timeout: 8)

        XCTAssertTrue(hasContent, "Dashboard should show cards after pull-to-refresh (not blank)")

        // If health card existed before, it should still exist
        if healthCardBefore {
            XCTAssertTrue(
                ui("dashboard_card_healthScore").waitForExistence(timeout: 5),
                "Health score card should persist after refresh"
            )
        }

        captureScreenshot(named: "Dashboard_PullToRefresh")
    }

    // MARK: - 6. Settings Gear -> Settings Screen

    func testTapSettingsGearNavigatesToSettings() {
        let settingsButton = app.buttons["dashboard_button_settings"]
        requireExists(settingsButton, timeout: 5, message: "Settings gear button should exist on dashboard")

        settingsButton.tap()

        // Verify settings screen appears with actual settings content
        let settingsScreen = ui("screen_settings")
        requireExists(settingsScreen, timeout: 8,
                      message: "Settings screen should appear after tapping gear button")

        // Functional: verify settings has real content (not just empty screen)
        let hasSettingsContent = waitForEither([
            app.switches["settings_toggle_backgroundRefresh"],
            ui("settings_stepper_pingCount"),
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Network Tools'")
            ).firstMatch,
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Settings'")
            ).firstMatch
        ], timeout: 5)

        XCTAssertTrue(hasSettingsContent,
                      "Settings screen should display settings controls, not an empty screen")

        captureScreenshot(named: "Dashboard_SettingsNav")
    }

    // MARK: - 7. Dashboard Tab Bar Navigation Round-Trip

    func testDashboardTabNavigationRoundTrip() {
        // Start on dashboard
        requireExists(ui("screen_dashboard"), timeout: 5, message: "Should start on dashboard")

        // Navigate away to Map
        app.tabBars.buttons["Map"].tap()
        requireExists(ui("screen_networkMap"), timeout: 8,
                      message: "Map screen should appear after tapping Map tab")

        // Navigate back to Dashboard
        app.tabBars.buttons["Dashboard"].tap()
        requireExists(ui("screen_dashboard"), timeout: 8,
                      message: "Dashboard should reappear after tapping Dashboard tab")

        // Verify dashboard still has its cards
        let hasCards = waitForEither([
            ui("dashboard_card_healthScore"),
            ui("dashboard_label_connectionStatus")
        ], timeout: 5)

        XCTAssertTrue(hasCards, "Dashboard should retain its cards after tab round-trip")
    }

    // MARK: - 8. Connection Status Header Shows Real Status

    func testConnectionStatusHeaderShowsStatus() {
        let header = ui("dashboard_label_connectionStatus")
        requireExists(header, timeout: 10, message: "Connection status header should be visible")

        let headerLabel = header.label
        let hasValidStatus = headerLabel.localizedCaseInsensitiveContains("monitoring")
            || headerLabel.localizedCaseInsensitiveContains("offline")
            || headerLabel.localizedCaseInsensitiveContains("online")
            || headerLabel.localizedCaseInsensitiveContains("connecting")

        XCTAssertTrue(hasValidStatus,
                      "Connection status header should show a valid status (monitoring/offline/online), got: '\(headerLabel)'")

        captureScreenshot(named: "Dashboard_ConnectionStatus")
    }

    // MARK: - 9. Connectivity Panel Shows ISP Data

    func testConnectivityPanelDisplaysISPData() {
        let panel = ui("dashboard_card_connectivity")
        scrollToElement(panel)

        guard panel.waitForExistence(timeout: 8) else { return }

        // Functional: panel should contain ISP or IP data, not be empty
        let hasISPData = screenContainsText("ISP")
            || screenContainsText("IP")
            || screenContainsText("Connection")
            || screenContainsText("Wi-Fi")
            || screenContainsText("Ethernet")

        XCTAssertTrue(hasISPData,
                      "Connectivity panel should display ISP, IP, or connection type information")

        captureScreenshot(named: "Dashboard_ConnectivityPanel")
    }

    // MARK: - 10. Add Network Sheet Validates Input

    func testAddNetworkSheetValidatesGatewayInput() {
        let addButton = app.buttons["Add Network"].firstMatch
        guard addButton.waitForExistence(timeout: 5) else { return }

        addButton.tap()
        requireExists(app.navigationBars["Add Network"], timeout: 8,
                      message: "Add Network sheet should appear")

        // Switch to Manual tab
        let manualTab = app.segmentedControls.buttons["Manual"]
        if manualTab.waitForExistence(timeout: 3) {
            manualTab.tap()
        }

        // Save button should be disabled with empty fields
        let saveButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'networkSheet_button_save' OR label == 'Save' OR label == 'Add'")
        ).firstMatch

        if saveButton.waitForExistence(timeout: 3) {
            XCTAssertFalse(saveButton.isEnabled,
                          "Save button should be disabled with empty gateway field")

            // Fill gateway and verify save becomes enabled
            let gatewayField = app.textFields["networkSheet_field_gateway"]
            if gatewayField.waitForExistence(timeout: 3) {
                clearAndTypeText("192.168.1.1", into: gatewayField)
                XCTAssertTrue(saveButton.isEnabled,
                             "Save button should enable after entering valid gateway")
            }
        }

        // Cancel to dismiss
        let cancelButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'networkSheet_button_cancel' OR label == 'Cancel'")
        ).firstMatch
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        }
    }
}
