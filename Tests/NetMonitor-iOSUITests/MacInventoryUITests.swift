import XCTest

/// #585 user flow: with the paired Mac connected, the device list shows the Mac's inventory. The
/// banner says so, a device both know reads the Mac's state "from your Mac" with "Seen by this
/// iPhone at …" apart, and a device only the Mac knows is listed. When the link drops, the list
/// falls back to the phone's own scans: no banner, no Mac-only device, no "from your Mac".
///
/// Against the in-app fake Mac (`--fake-mac-pairing`, #590) with `UITEST_FAKE_MAC_INVENTORY=1`,
/// which advertises `inventory.v1` and answers `refreshDevices` with uitest-device-0 (online) and
/// a doorbell only it knows, and stops `UITEST_FAKE_MAC_STOP_AFTER` seconds after sending it.
/// The phone's rows come from the UI-test scan (`UITEST_FAKE_DEVICES=1`). Screenshots are cropped
/// to the list's rows and banner; every device is a fixture.
@MainActor
final class MacInventoryUITests: PresenceUITestCase {
    private static let code = "14D2P-F2DBS-QQG28-T5CY4-TQKFF-K"
    private static let dropAfter: TimeInterval = 50

    override var additionalLaunchArguments: [String] { ["--fake-mac-pairing"] }
    override var additionalLaunchEnvironment: [String: String] {
        [
            "UITEST_PAIRING_CODE": Self.code, "UITEST_FAKE_DEVICES": "1", "UITEST_FAKE_MAC_INVENTORY": "1",
            "UITEST_FAKE_MAC_STOP_AFTER": "\(Int(Self.dropAfter))"
        ]
    }

    func testConnectedMacInventoryThenFallbackWhenTheLinkDrops() {
        scan()
        pairWithFakeMac()
        let sentAt = Date()
        openDeviceList()

        // Connected: the list is the Mac's.
        let banner = ui("deviceList_banner_macInventory")
        requireExists(banner, timeout: 10, message: "The list should say it comes from the Mac")
        XCTAssertTrue(banner.label.hasPrefix("From your Mac · scanned"), "Banner: \(banner.label)")

        let shared = row("192.168.1.10")
        requireExists(shared, timeout: 5, message: "The device both know should be listed")
        expectValue(shared, startsWith: "Online, from your Mac, last seen", "The Mac's state, with its source")
        XCTAssertTrue(value(shared).contains("Seen by this iPhone at"), "The phone's own sighting, apart: \(value(shared))")

        let phoneOnly = row("192.168.1.11")
        requireExists(phoneOnly, timeout: 5, message: "A device only the phone knows should be listed")
        XCTAssertFalse(value(phoneOnly).contains("from your Mac"), "The phone's own state: \(value(phoneOnly))")
        XCTAssertTrue(value(phoneOnly).contains("Seen by this iPhone at"), "Labelled as the phone's: \(value(phoneOnly))")
        captureElement(banner, named: "585-01-banner-from-your-mac")
        captureElement(shared, named: "585-02-device-both-know")
        captureElement(phoneOnly, named: "585-03-device-only-the-phone-knows")

        let doorbell = row("192.168.1.60")
        scrollToElement(doorbell)
        requireExists(doorbell, timeout: 5, message: "A device only the Mac knows should be listed")
        XCTAssertTrue(value(doorbell).hasPrefix("Online, from your Mac"), "The Mac's state: \(value(doorbell))")
        captureElement(doorbell, named: "585-04-device-only-the-mac-knows")
        doorbell.tap()
        XCTAssertFalse(ui("deviceDetail_label_status").waitForExistence(timeout: 2), "A device only the Mac knows opens nothing")

        // Device detail says where its status comes from.
        scrollToElement(shared)
        shared.tap()
        let status = ui("deviceDetail_label_status")
        requireExists(status, timeout: 8, message: "Device detail should open")
        XCTAssertTrue(status.label.hasPrefix("Online, from your Mac"), "Detail status: \(status.label)")
        requireExists(ui("deviceDetail_label_phoneSighting"), message: "Detail shows the phone's own sighting apart")
        captureElement(status, named: "585-05-detail-status-from-your-mac")
        app.navigationBars.buttons.firstMatch.tap()

        // The link drops (the fake Mac stops): back to the phone's own data, never a frozen "Online".
        let remaining = Self.dropAfter - Date().timeIntervalSince(sentAt)
        XCTAssertTrue(waitForDisappearance(banner, timeout: max(remaining, 0) + 30), "The banner goes when the link drops")
        requireExists(shared, timeout: 5, message: "The phone's row stays")
        XCTAssertFalse(value(shared).contains("from your Mac"), "No Mac state after the drop: \(value(shared))")
        XCTAssertFalse(value(shared).contains("Seen by this iPhone"), "Only one source again: \(value(shared))")
        XCTAssertFalse(row("192.168.1.60").exists, "The device only the Mac knew is gone")
        captureElement(shared, named: "585-06-fallback-after-link-drop")
    }

    // MARK: - Helpers

    private func pairWithFakeMac() {
        requireExists(app.tabBars.buttons["Dashboard"], message: "Dashboard tab should exist").tap()
        let settingsButton = app.buttons["dashboard_button_settings"]
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        } else {
            requireExists(app.navigationBars.buttons.firstMatch, message: "A navigation bar button should exist for settings").tap()
        }
        requireExists(app.byID("screen_settings"), timeout: 8, message: "Settings screen should open")
        let connect = app.buttons["settings_button_connectMac"]
        scrollToElement(connect)
        requireExists(connect, message: "Connect to Mac").tap()
        requireExists(app.buttons["pairing_row_Test Mac"], timeout: 8, message: "The fake Mac should be listed").tap()
        let field = requireExists(app.textFields["pairMac_textfield_code"], timeout: 5, message: "The code field should show")
        field.tap()
        field.typeText(Self.code + "\n")
        requireExists(app.buttons["pairMac_button_pairWithCode"], message: "Pair button").tap()
        requireExists(app.buttons["pairMac_button_codesMatch"], timeout: 8, message: "They Match").tap()
        requireExists(app.staticTexts["pairMac_label_paired"], timeout: 10, message: "The Mac confirms and the phone pins it")
        app.buttons["pairMac_button_done"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 10), "The paired link comes up")
        // Close the sheet without Cancel, which disconnects.
        app.swipeDown(velocity: .fast)
        if app.byID("screen_macPairing").exists {
            app.navigationBars.firstMatch.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(waitForDisappearance(app.byID("screen_macPairing"), timeout: 5), "The pairing sheet closes")
    }

    /// A screenshot of one element only: the repo is public.
    private func captureElement(_ element: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
