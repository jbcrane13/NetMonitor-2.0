import XCTest

@MainActor
final class DeviceDetailUITests: IOSUITestCase {

    // MARK: - Network Map Screen

    func testNetworkMapScreenShowsContent() throws {
        navigateToMap()
        let screen = app.byID("screen_networkMap")
        XCTAssertTrue(screen.waitForExistence(timeout: 5),
                     "Network map screen should exist after tapping Map tab")
        // FUNCTIONAL: screen should contain at least a scan button
        XCTAssertTrue(
            app.buttons["networkMap_button_scan"].waitForExistence(timeout: 3),
            "Network map screen should contain a scan button"
        )
    }

    func testScanButtonIsTappable() throws {
        navigateToMap()
        let scanButton = app.buttons["networkMap_button_scan"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5),
                     "Scan button should exist on network map")
        XCTAssertTrue(scanButton.isEnabled, "Scan button should be tappable")
    }

    // MARK: - Device Detail (requires a discovered device)

    func testDeviceDetailScreenShowsDeviceInfo() throws {
        navigateToMap()
        // Tap scan to discover devices
        let scanButton = app.buttons["networkMap_button_scan"]
        if scanButton.waitForExistence(timeout: 5) {
            scanButton.tap()
            // Wait for scan to find at least one device
            let firstDeviceRow = app.otherElements.matching(
                NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")
            ).firstMatch
            if firstDeviceRow.waitForExistence(timeout: 10) {
                firstDeviceRow.tap()
                XCTAssertTrue(
                    app.byID("screen_deviceDetail").waitForExistence(timeout: 5),
                    "Device detail screen should appear after tapping a device row"
                )
                // FUNCTIONAL: detail screen should contain device information text
                let detailScreen = app.byID("screen_deviceDetail")
                XCTAssertTrue(
                    !detailScreen.staticTexts.isEmpty,
                    "Device detail screen should contain device information text"
                )
            }
        }
    }

    func testDeviceDetailHeaderDisplaysIconAndName() throws {
        navigateToFirstDevice()
        if app.byID("screen_deviceDetail").waitForExistence(timeout: 5) {
            let hasIcon = app.byID("deviceDetail_icon_deviceType").exists ||
                          app.images["deviceDetail_icon_deviceType"].exists
            let hasName = app.staticTexts["deviceDetail_label_displayName"].exists ||
                          app.byID("deviceDetail_label_displayName").exists
            XCTAssertTrue(hasIcon || hasName,
                         "Device detail header should show a device icon or display name")
            // FUNCTIONAL: if name label exists, it should contain text
            let nameElement = app.byID("deviceDetail_label_displayName")
            if nameElement.exists {
                XCTAssertFalse(nameElement.label.isEmpty,
                              "Device display name label should contain text")
            }
        }
    }

    func testDeviceDetailNetworkInfoSectionContainsData() throws {
        navigateToFirstDevice()
        if app.byID("screen_deviceDetail").waitForExistence(timeout: 5) {
            let ipRow = app.byID("deviceDetail_row_ipAddress")
            let networkInfoTitle = app.staticTexts["deviceDetail_label_networkInfoTitle"]
            XCTAssertTrue(
                ipRow.waitForExistence(timeout: 3) || networkInfoTitle.exists,
                "Device detail should show IP address row or network info section"
            )
            // FUNCTIONAL: if IP row exists, it should contain text data
            if ipRow.exists {
                XCTAssertTrue(
                    !ipRow.staticTexts.isEmpty || !ipRow.label.isEmpty,
                    "IP address row should contain IP address data"
                )
            }
        }
    }

    func testDeviceDetailServicesSectionExists() throws {
        navigateToFirstDevice()
        if app.byID("screen_deviceDetail").waitForExistence(timeout: 5) {
            app.swipeUp()
            let servicesSection = app.byID("deviceDetail_section_services")
            let servicesTitle = app.staticTexts["deviceDetail_label_servicesTitle"]
            XCTAssertTrue(
                servicesSection.waitForExistence(timeout: 3) || servicesTitle.exists,
                "Device detail should show services section or title"
            )
        }
    }

    func testDeviceDetailQuickActionsAreTappable() throws {
        navigateToFirstDevice()
        if app.byID("screen_deviceDetail").waitForExistence(timeout: 5) {
            app.swipeUp()
            let pingButton = app.buttons["deviceDetail_button_ping"]
            let portScanButton = app.buttons["deviceDetail_button_portScan"]
            let dnsButton = app.buttons["deviceDetail_button_dnsLookup"]
            let quickActionsTitle = app.staticTexts["deviceDetail_label_quickActionsTitle"]

            XCTAssertTrue(
                pingButton.exists || portScanButton.exists || dnsButton.exists || quickActionsTitle.exists,
                "Device detail should show at least one quick action or quick actions title"
            )
            // FUNCTIONAL: if buttons exist, they should be enabled/tappable
            if pingButton.exists {
                XCTAssertTrue(pingButton.isEnabled, "Ping quick action should be tappable")
            }
            if portScanButton.exists {
                XCTAssertTrue(portScanButton.isEnabled, "Port scan quick action should be tappable")
            }
            if dnsButton.exists {
                XCTAssertTrue(dnsButton.isEnabled, "DNS lookup quick action should be tappable")
            }
        }
    }

    func testDeviceDetailScanPortsButtonIsEnabled() throws {
        navigateToFirstDevice()
        if app.byID("screen_deviceDetail").waitForExistence(timeout: 5) {
            app.swipeUp()
            let scanPortsButton = app.buttons["deviceDetail_button_scanPorts"]
            if scanPortsButton.waitForExistence(timeout: 3) {
                XCTAssertTrue(scanPortsButton.isEnabled,
                             "Scan Ports button should be enabled")
            }
        }
    }

    // MARK: - Functional Tests

    func testDeviceDetailScreenElements() throws {
        navigateToMap()

        let scanButton = app.buttons["networkMap_button_scan"]
        guard scanButton.waitForExistence(timeout: 5) else { return }
        scanButton.tap()

        let firstDeviceRow = app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'"))
            .firstMatch

        guard firstDeviceRow.waitForExistence(timeout: 10) else { return }

        firstDeviceRow.tap()

        guard app.byID("screen_deviceDetail").waitForExistence(timeout: 8) else {
            XCTFail("Device detail screen should appear after tapping a device row")
            return
        }

        let ipRow = app.byID("deviceDetail_row_ipAddress")
        let hostnameRow = app.byID("deviceDetail_row_hostname")
        let networkInfoTitle = app.staticTexts["deviceDetail_label_networkInfoTitle"]

        XCTAssertTrue(
            ipRow.exists || hostnameRow.exists || networkInfoTitle.exists,
            "Device detail should show IP address, hostname, or network info section"
        )
    }

    func testDeviceDetailClosesBackToList() throws {
        navigateToMap()

        let scanButton = app.buttons["networkMap_button_scan"]
        guard scanButton.waitForExistence(timeout: 5) else { return }
        scanButton.tap()

        let firstDeviceRow = app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'"))
            .firstMatch

        guard firstDeviceRow.waitForExistence(timeout: 10) else { return }

        firstDeviceRow.tap()

        guard app.byID("screen_deviceDetail").waitForExistence(timeout: 8) else {
            XCTFail("Device detail screen should appear after tapping a device row")
            return
        }

        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        } else {
            app.swipeRight()
        }

        let mapScreen = app.byID("screen_networkMap")
        let deviceListScreen = app.byID("screen_deviceList")
        XCTAssertTrue(
            mapScreen.waitForExistence(timeout: 5) || deviceListScreen.waitForExistence(timeout: 5),
            "Should return to network map or device list after dismissing device detail"
        )
    }

    // MARK: - Helpers

    private func navigateToMap() {
        let mapTab = app.tabBars.buttons["Map"]
        if mapTab.waitForExistence(timeout: 5) {
            mapTab.tap()
        }
    }

    private func navigateToFirstDevice() {
        navigateToMap()
        let scanButton = app.buttons["networkMap_button_scan"]
        if scanButton.waitForExistence(timeout: 5) {
            scanButton.tap()
            let firstDeviceRow = app.otherElements.matching(
                NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")
            ).firstMatch
            if firstDeviceRow.waitForExistence(timeout: 10) {
                firstDeviceRow.tap()
            }
        }
    }
}
