import XCTest

final class DashboardUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Dashboard is the default tab
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testDashboardScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_dashboard"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))
    }

    // MARK: - Settings Navigation

    func testSettingsButtonExists() throws {
        XCTAssertTrue(app.buttons["dashboard_button_settings"].waitForExistence(timeout: 5))
    }

    func testSettingsButtonNavigatesToSettings() throws {
        app.buttons["dashboard_button_settings"].tap()
        XCTAssertTrue(app.otherElements["screen_settings"].waitForExistence(timeout: 5))
    }

    // MARK: - Connection Status Header

    func testConnectionStatusHeaderExists() throws {
        XCTAssertTrue(app.otherElements["dashboard_header_connectionStatus"].waitForExistence(timeout: 5))
    }

    // MARK: - Dashboard Cards

    func testSessionCardExists() throws {
        XCTAssertTrue(app.otherElements["dashboard_card_session"].waitForExistence(timeout: 5))
    }

    func testWiFiCardExists() throws {
        XCTAssertTrue(app.otherElements["dashboard_card_wifi"].waitForExistence(timeout: 5))
    }

    func testGatewayCardExists() throws {
        XCTAssertTrue(app.otherElements["dashboard_card_gateway"].waitForExistence(timeout: 5))
    }

    func testISPCardExists() throws {
        let ispCard = app.otherElements["dashboard_card_isp"]
        app.swipeUp()
        XCTAssertTrue(ispCard.waitForExistence(timeout: 5))
    }

    func testLocalDevicesCardExists() throws {
        let devicesCard = app.otherElements["dashboard_card_localDevices"]
        app.swipeUp()
        XCTAssertTrue(devicesCard.waitForExistence(timeout: 5))
    }

    // MARK: - Local Devices Navigation

    func testLocalDevicesCardNavigatesToDeviceList() throws {
        let devicesCard = app.otherElements["dashboard_card_localDevices"]
        app.swipeUp()
        if devicesCard.waitForExistence(timeout: 5) {
            devicesCard.tap()
            XCTAssertTrue(app.otherElements["deviceList_screen"].waitForExistence(timeout: 5))
        }
    }

    // MARK: - Pull to Refresh

    func testPullToRefreshExists() throws {
        let dashboard = app.otherElements["screen_dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
        // Pull to refresh gesture
        let start = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = dashboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
    }
}
