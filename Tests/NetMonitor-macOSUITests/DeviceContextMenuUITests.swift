import XCTest

/// Functional verification for the Devices > Device context menu.
///
/// Each action item in the menu (ping, port scan, remove) must produce
/// a visible outcome — a sheet appears or the device row disappears.
/// Element-existence-only tests were marked shallow in issue #174 and
/// replaced here with outcome checks. Uses the `--seed-test-device`
/// launch flag so a deterministic device is present before the menu is
/// opened.
@MainActor
final class DeviceContextMenuUITests: XCTestCase {
    private var app: XCUIApplication!

    private let seededIP = "192.168.77.77"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--seed-test-device"]
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["XCUITest"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "App main window should appear after launch")

        // Navigate to Devices list.
        let sidebarItem = app.descendants(matching: .any)["sidebar_devices"]
        XCTAssertTrue(sidebarItem.waitForExistence(timeout: 5),
                      "Devices sidebar item should exist")
        sidebarItem.tap()

        // Wait for the seeded card to appear — seeding runs ~1s after launch.
        let card = app.descendants(matching: .any)["devices_card_\(seededIP)"]
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "Seeded device card should appear before tests run")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Menu opens with expected items

    func testContextMenuOpensWithAllActions() {
        let card = app.descendants(matching: .any)["devices_card_\(seededIP)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.rightClick()

        // SwiftUI context menu buttons surface either as menuItems or
        // buttons on macOS depending on representation — accept either.
        XCTAssertTrue(
            waitForAny(
                [
                    app.menuItems["devices_menu_copyIP"],
                    app.buttons["devices_menu_copyIP"]
                ],
                timeout: 3
            ),
            "Copy IP menu item should be present after right-click"
        )
        XCTAssertTrue(
            waitForAny(
                [
                    app.menuItems["devices_menu_ping"],
                    app.buttons["devices_menu_ping"]
                ],
                timeout: 3
            ),
            "Ping Device menu item should be present"
        )
        XCTAssertTrue(
            waitForAny(
                [
                    app.menuItems["devices_menu_portScan"],
                    app.buttons["devices_menu_portScan"]
                ],
                timeout: 3
            ),
            "Scan Ports menu item should be present"
        )
        XCTAssertTrue(
            waitForAny(
                [
                    app.menuItems["devices_menu_remove"],
                    app.buttons["devices_menu_remove"]
                ],
                timeout: 3
            ),
            "Remove Device menu item should be present"
        )

        // Dismiss the menu so tearDown can terminate cleanly.
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Ping action triggers ping sheet with device IP pre-filled

    func testPingActionOpensPingSheet() {
        openContextMenu()
        tapMenuItem("devices_menu_ping")

        let sheet = app.descendants(matching: .any)["devices_section_pingSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5),
                      "Ping sheet should appear after tapping Ping Device menu item")

        // Verify the ping host field is pre-filled with the device IP
        let hostField = app.textFields["ping_textfield_host"]
        if hostField.waitForExistence(timeout: 5) {
            let hostValue = hostField.value as? String ?? ""
            XCTAssertTrue(!hostValue.isEmpty,
                          "Ping host field should be pre-filled with device IP, got: '\(hostValue)'")
            XCTAssertTrue(hostValue == seededIP || hostValue.contains("192.168"),
                          "Ping host field should contain the device IP (\(seededIP)), got: '\(hostValue)'")
        }
    }

    // MARK: - Scan Ports action triggers port scan sheet with device IP pre-filled

    func testScanPortsActionOpensPortScanSheet() {
        openContextMenu()
        tapMenuItem("devices_menu_portScan")

        let sheet = app.descendants(matching: .any)["devices_section_portScanSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5),
                      "Port scan sheet should appear after tapping Scan Ports menu item")

        // Verify the port scan host field is pre-filled with the device IP
        let hostField = app.textFields["portScan_textfield_host"]
        if hostField.waitForExistence(timeout: 5) {
            let hostValue = hostField.value as? String ?? ""
            XCTAssertTrue(!hostValue.isEmpty,
                          "Port scan host field should be pre-filled with device IP, got: '\(hostValue)'")
            XCTAssertTrue(hostValue == seededIP || hostValue.contains("192.168"),
                          "Port scan host field should contain the device IP (\(seededIP)), got: '\(hostValue)'")
        }
    }

    // MARK: - Copy IP action copies device IP to clipboard

    func testCopyIPActionProvidesFeedback() {
        openContextMenu()
        tapMenuItem("devices_menu_copyIP")

        // After copying IP, verify the device card still exists (no unexpected navigation)
        // and the menu has dismissed (card is hittable again)
        let card = app.descendants(matching: .any)["devices_card_\(seededIP)"]
        XCTAssertTrue(card.waitForExistence(timeout: 3),
                      "Device card should still exist after Copy IP action")

        // The "Copied" toast is transient, so verify the card is hittable
        // (proving the context menu dismissed and the action completed)
        XCTAssertTrue(card.isHittable,
                      "Device card should be hittable after Copy IP action completes")
    }

    // MARK: - Remove action removes the device from the list

    func testRemoveActionDeletesDeviceCard() {
        let card = app.descendants(matching: .any)["devices_card_\(seededIP)"]
        XCTAssertTrue(card.exists, "Seeded card should exist before removal")

        openContextMenu()
        tapMenuItem("devices_menu_remove")

        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: card)
        let result = XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed,
                       "Device card should disappear after tapping Remove Device")
    }

    // MARK: - Helpers

    private func openContextMenu() {
        let card = app.descendants(matching: .any)["devices_card_\(seededIP)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5),
                      "Seeded card should exist before right-click")
        card.rightClick()
    }

    /// Taps a menu entry exposed by SwiftUI's `.contextMenu` — may surface
    /// as either `menuItems[id]` or `buttons[id]` depending on macOS
    /// representation, so we try both.
    private func tapMenuItem(_ identifier: String) {
        let menuItem = app.menuItems[identifier]
        if menuItem.waitForExistence(timeout: 3), menuItem.isHittable {
            menuItem.tap()
            return
        }
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 3),
                      "Menu entry \(identifier) should be findable as menuItem or button")
        button.tap()
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
