import XCTest

final class DeviceDetailUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Map tab to find devices
        app.tabBars.buttons["Map"].tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Network Map Screen

    func testNetworkMapScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_networkMap"].waitForExistence(timeout: 5))
    }

    func testScanButtonExists() throws {
        XCTAssertTrue(app.buttons["networkMap_button_scan"].waitForExistence(timeout: 5))
    }

    // MARK: - Device Detail (requires a discovered device)

    func testDeviceDetailScreenIdentifier() throws {
        // Tap scan to discover devices
        let scanButton = app.buttons["networkMap_button_scan"]
        if scanButton.waitForExistence(timeout: 5) {
            scanButton.tap()
            // Wait for scan to find at least one device
            sleep(3)
            // Try to tap a device row if available
            let firstDeviceRow = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")).firstMatch
            if firstDeviceRow.waitForExistence(timeout: 10) {
                firstDeviceRow.tap()
                XCTAssertTrue(app.otherElements["screen_deviceDetail"].waitForExistence(timeout: 5))
            }
        }
    }

    func testDeviceDetailHeaderElements() throws {
        navigateToFirstDevice()
        if app.otherElements["screen_deviceDetail"].waitForExistence(timeout: 5) {
            XCTAssertTrue(app.otherElements["deviceDetail_icon_deviceType"].exists ||
                          app.images["deviceDetail_icon_deviceType"].exists)
            XCTAssertTrue(app.staticTexts["deviceDetail_label_displayName"].exists ||
                          app.otherElements["deviceDetail_label_displayName"].exists)
        }
    }

    func testDeviceDetailNetworkInfoSection() throws {
        navigateToFirstDevice()
        if app.otherElements["screen_deviceDetail"].waitForExistence(timeout: 5) {
            XCTAssertTrue(app.otherElements["deviceDetail_row_ipAddress"].waitForExistence(timeout: 3) ||
                          app.staticTexts["deviceDetail_label_networkInfoTitle"].exists)
        }
    }

    func testDeviceDetailServicesSection() throws {
        navigateToFirstDevice()
        if app.otherElements["screen_deviceDetail"].waitForExistence(timeout: 5) {
            app.swipeUp()
            XCTAssertTrue(app.otherElements["deviceDetail_section_services"].waitForExistence(timeout: 3) ||
                          app.staticTexts["deviceDetail_label_servicesTitle"].exists)
        }
    }

    func testDeviceDetailQuickActions() throws {
        navigateToFirstDevice()
        if app.otherElements["screen_deviceDetail"].waitForExistence(timeout: 5) {
            app.swipeUp()
            let pingButton = app.buttons["deviceDetail_button_ping"]
            let portScanButton = app.buttons["deviceDetail_button_portScan"]
            let dnsButton = app.buttons["deviceDetail_button_dnsLookup"]
            // At least one action should exist
            XCTAssertTrue(pingButton.exists || portScanButton.exists || dnsButton.exists ||
                          app.staticTexts["deviceDetail_label_quickActionsTitle"].exists)
        }
    }

    func testDeviceDetailScanPortsButton() throws {
        navigateToFirstDevice()
        if app.otherElements["screen_deviceDetail"].waitForExistence(timeout: 5) {
            app.swipeUp()
            let scanPortsButton = app.buttons["deviceDetail_button_scanPorts"]
            if scanPortsButton.waitForExistence(timeout: 3) {
                XCTAssertTrue(scanPortsButton.isEnabled)
            }
        }
    }

    // MARK: - Helpers

    private func navigateToFirstDevice() {
        let scanButton = app.buttons["networkMap_button_scan"]
        if scanButton.waitForExistence(timeout: 5) {
            scanButton.tap()
            sleep(3)
            let firstDeviceRow = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")).firstMatch
            if firstDeviceRow.waitForExistence(timeout: 10) {
                firstDeviceRow.tap()
            }
        }
    }
}
