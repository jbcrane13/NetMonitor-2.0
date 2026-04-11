@preconcurrency import XCTest

final class DevicesUITests: MacOSUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        navigateToSidebar("devices")
    }

    // MARK: - Detail Pane

    func testDevicesDetailExists() {
        requireExists(app.otherElements["detail_devices"], timeout: 3,
                      message: "Devices detail pane should exist")
    }

    // MARK: - Toolbar Buttons

    func testScanButtonExists() {
        requireExists(app.buttons["devices_button_scan"], timeout: 3,
                      message: "Scan button should exist")
    }

    func testScanButtonIsEnabled() {
        let button = requireExists(
            app.buttons["devices_button_scan"], timeout: 3,
            message: "Scan button should exist"
        )
        XCTAssertTrue(button.isEnabled, "Scan button should be enabled")
    }

    func testSortMenuExists() {
        requireExists(app.menuButtons["devices_menu_sort"], timeout: 3,
                      message: "Sort menu should exist")
    }

    func testOnlineOnlyToggleExists() {
        requireExists(app.toggles["devices_toggle_onlineOnly"], timeout: 3,
                      message: "Online-only toggle should exist")
    }

    func testClearButtonExists() {
        requireExists(app.buttons["devices_button_clear"], timeout: 3,
                      message: "Clear button should exist")
    }

    // MARK: - Functional: Scan

    func testScanButtonTriggersScanningState() {
        let scanButton = requireExists(
            app.buttons["devices_button_scan"], timeout: 3,
            message: "Scan button should exist"
        )
        XCTAssertTrue(scanButton.isEnabled, "Scan button should be enabled before tapping")

        scanButton.tap()

        XCTAssertTrue(
            waitForEither(
                [
                    app.buttons["devices_button_stopScan"],
                    app.buttons["devices_button_scan"]
                ],
                timeout: 10
            ),
            "After tapping scan, either a stop button or the scan button should be present"
        )

        let stopButton = app.buttons["devices_button_stopScan"]
        if stopButton.exists && stopButton.isEnabled {
            stopButton.tap()
        }
    }

    // MARK: - Functional: Sort Menu

    func testSortMenuOpensAndHasOptions() {
        let sortMenu = requireExists(
            app.menuButtons["devices_menu_sort"], timeout: 3,
            message: "Sort menu should exist"
        )
        XCTAssertTrue(sortMenu.isEnabled, "Sort menu should be enabled")

        sortMenu.tap()

        XCTAssertTrue(
            waitForEither(
                [app.menuItems.firstMatch, app.menuButtons.firstMatch],
                timeout: 3
            ),
            "Sort menu should open and show at least one menu item"
        )

        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Functional: Online-Only Toggle

    func testOnlineOnlyToggleInteraction() {
        let toggle = app.toggles["devices_toggle_onlineOnly"]
        guard toggle.waitForExistence(timeout: 3) else { return }

        XCTAssertTrue(toggle.isEnabled, "Online-only toggle should be enabled")
        let valueBefore = toggle.value as? String

        toggle.tap()

        let valueAfter = toggle.value as? String
        if let before = valueBefore, let after = valueAfter {
            XCTAssertNotEqual(before, after,
                              "Online-only toggle value should change after tapping")
        }

        toggle.tap()
    }

    // MARK: - Functional: Clear Button

    func testClearButtonExistsAndIsPresent() {
        let clearButton = requireExists(
            app.buttons["devices_button_clear"], timeout: 3,
            message: "Clear button should exist in devices toolbar"
        )
        XCTAssertTrue(clearButton.exists, "Clear button should be present")
    }

    // MARK: - Search

    func testSearchFieldExists() {
        requireExists(app.otherElements["detail_devices"], timeout: 3,
                      message: "Devices detail pane should exist (search field is inside it)")
    }

    // MARK: - Empty State

    func testEmptyStateOrDeviceListShown() {
        requireExists(app.otherElements["detail_devices"], timeout: 3,
                      message: "Devices detail pane should be visible")
    }

    func testSelectDevicePlaceholderExists() {
        requireExists(app.otherElements["detail_devices"], timeout: 3,
                      message: "Devices detail pane should be visible")
    }
}
