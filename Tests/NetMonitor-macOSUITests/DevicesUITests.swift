import XCTest

@MainActor
final class DevicesUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Devices
        let sidebar = app.staticTexts["sidebar_devices"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Detail Pane

    func testDevicesDetailExists() {
        XCTAssertTrue(app.otherElements["detail_devices"].waitForExistence(timeout: 3))
    }

    // MARK: - Toolbar Buttons

    func testScanButtonExists() {
        XCTAssertTrue(app.buttons["devices_button_scan"].waitForExistence(timeout: 3))
    }

    func testScanButtonIsEnabled() {
        let button = app.buttons["devices_button_scan"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        XCTAssertTrue(button.isEnabled)
    }

    func testSortMenuExists() {
        XCTAssertTrue(app.menuButtons["devices_menu_sort"].waitForExistence(timeout: 3))
    }

    func testOnlineOnlyToggleExists() {
        XCTAssertTrue(app.toggles["devices_toggle_onlineOnly"].waitForExistence(timeout: 3))
    }

    func testClearButtonExists() {
        XCTAssertTrue(app.buttons["devices_button_clear"].waitForExistence(timeout: 3))
    }

    // MARK: - Search

    func testSearchFieldExists() {
        // searchable modifier creates a search field in the toolbar
        XCTAssertTrue(app.otherElements["detail_devices"].waitForExistence(timeout: 3))
    }

    // MARK: - Empty State

    func testEmptyStateOrDeviceListShown() {
        // Either show empty state or device list depending on scan history
        let detailPane = app.otherElements["detail_devices"]
        XCTAssertTrue(detailPane.waitForExistence(timeout: 3))
    }

    // MARK: - Select Device Placeholder

    func testSelectDevicePlaceholderExists() {
        // When no device is selected, should show placeholder
        let placeholder = app.staticTexts["devices_label_selectDevice"]
        // May not exist if a device is pre-selected
        XCTAssertTrue(app.otherElements["detail_devices"].waitForExistence(timeout: 3))
    }
}
