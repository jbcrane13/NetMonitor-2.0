import XCTest

/// Regression coverage for #318: tapping a device row on the dashboard's
/// device list must push the detail screen immediately, not 5-20s later
/// after the list silently reloads.
///
/// This launches with `UITEST_FAKE_DEVICES=1`, which makes
/// `DashboardViewModel` publish a small deterministic device set that keeps
/// re-publishing on a timer (see `DashboardViewModel.startUITestFakeDeviceFeedIfNeeded()`).
/// That reproduces the actual bug condition -- the dashboard's view model
/// keeps publishing while the device list is on screen -- without depending
/// on real ARP/Bonjour discovery, which isn't reliably available on
/// automation hardware. Isolated in its own file/class so only this test
/// launches with the fixture; other dashboard UI tests are unaffected.
@MainActor
final class DashboardDeviceDetailNavigationUITests: IOSUITestCase {

    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1"]
    }

    func testTapDeviceRowInDashboardDeviceListPushesDetailImmediately() throws {
        // Container identifiers can be duplicated/stamped over children on iOS 26,
        // so resolve via `.matching(identifier:).firstMatch` rather than a plain
        // subscript lookup.
        let devicesCard = app.descendants(matching: .any).matching(identifier: "dashboard_card_localDevices").firstMatch
        scrollToElement(devicesCard)
        requireExists(devicesCard, timeout: 10, message: "Local devices card should exist on dashboard")

        devicesCard.tap()

        let deviceListScreen = app.descendants(matching: .any).matching(identifier: "screen_deviceList").firstMatch
        requireExists(deviceListScreen, timeout: 8,
                      message: "Tapping local devices card should navigate to device list screen")

        let firstDeviceRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'deviceList_row_device_'")
        ).firstMatch
        requireExists(firstDeviceRow, timeout: 8,
                      message: "Fake device feed should populate at least one device row")

        firstDeviceRow.tap()

        let detailScreen = app.descendants(matching: .any).matching(identifier: "screen_deviceDetail").firstMatch
        XCTAssertTrue(
            detailScreen.waitForExistence(timeout: 2.5),
            "Device detail screen should push immediately (within ~2s) after tapping a device row"
        )

        captureScreenshot(named: "Dashboard_DeviceDetailImmediateNav")
    }
}
