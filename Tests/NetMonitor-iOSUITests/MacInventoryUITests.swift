import XCTest

/// #585 user flow: with the paired Mac connected, the device list shows the Mac's inventory. The
/// banner says so, a device both know reads the Mac's state "from your Mac" with "Seen by this
/// iPhone at …" apart, detail adds when it last changed, the dashboard counts the Mac's devices, and
/// a device only the Mac knows is listed. When the Mac leaves, the list falls back to the phone's own
/// scans: no banner, no Mac-only device, no "from your Mac". The Mac has the shared device offline
/// while the phone finds it, so a frozen Mac state can't pass for the fallback.
///
/// Against the in-app fake Mac (`--fake-mac-pairing`, #590) with `UITEST_FAKE_MAC_INVENTORY=1`,
/// which advertises `inventory.v1` and answers `refreshDevices` with uitest-device-0 (offline, last
/// seen 20 minutes before), uitest-device-2 (online inside the Mac's grace) and a doorbell only it
/// knows (online). The test makes it leave with the
/// Debug-only Settings control. The phone's rows come from the UI-test scan (`UITEST_FAKE_DEVICES=1`).
/// Screenshots are cropped to rows and labels; every device is a fixture.
@MainActor
final class MacInventoryUITests: PresenceUITestCase {
    private static let code = "14D2P-F2DBS-QQG28-T5CY4-TQKFF-K"

    override var additionalLaunchArguments: [String] { ["--fake-mac-pairing"] }
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_PAIRING_CODE": Self.code, "UITEST_FAKE_DEVICES": "1", "UITEST_FAKE_MAC_INVENTORY": "1"]
    }

    func testConnectedMacInventoryThenFallbackWhenTheMacLeaves() {
        scan()
        pairWithFakeMac()

        // The dashboard card counts the doorbell only the Mac knows: six devices, five online (the
        // Mac has uitest-device-0 offline).
        app.tabBars.buttons["Dashboard"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        let link = ui("dashboard_link_devices")
        scrollToElement(link)
        requireExists(link, timeout: 10, message: "The dashboard's devices card should exist")
        let counted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "5 online, 6 devices"), object: link)
        XCTAssertEqual(XCTWaiter().wait(for: [counted], timeout: 10), .completed, "One count, the Mac's devices in it: \(value(link))")
        // Clear of the tab bar: the card's header and first rows.
        app.swipeUp(velocity: .slow)
        captureElement(link, named: "585-00-dashboard-card")
        openDeviceList()

        // Connected: the list is the Mac's.
        let banner = ui("deviceList_banner_macInventory")
        requireExists(banner, timeout: 10, message: "The list should say it comes from the Mac")
        XCTAssertTrue(banner.label.hasPrefix("From your Mac · scanned"), "Banner: \(banner.label)")

        let shared = row("192.168.1.10")
        requireExists(shared, timeout: 5, message: "The device both know should be listed")
        expectValue(shared, startsWith: "Offline, from your Mac, last seen 20 min ago", "The Mac's state, with its source")
        XCTAssertTrue(value(shared).contains("Seen by this iPhone at"), "The phone's own scan saw it: \(value(shared))")

        let phoneOnly = row("192.168.1.11")
        requireExists(phoneOnly, timeout: 5, message: "A device only the phone knows should be listed")
        XCTAssertFalse(value(phoneOnly).contains("from your Mac"), "The phone's own state: \(value(phoneOnly))")
        XCTAssertTrue(value(phoneOnly).contains("Seen by this iPhone at"), "Labelled as the phone's: \(value(phoneOnly))")

        // Missed the Mac's latest scan but inside the Mac's grace: as the Mac app shows it, Online with
        // its real last seen, never "Not checked recently" (#583 grace, lead on item 7).
        let inGrace = row("192.168.1.12")
        requireExists(inGrace, timeout: 5, message: "The device inside the Mac's grace should be listed")
        expectValue(inGrace, startsWith: "Online, from your Mac, last seen 6 min ago", "The Mac's grace state")
        captureElement(banner, named: "585-01-banner-from-your-mac")
        captureElement(shared, named: "585-02-device-both-know")
        captureElement(phoneOnly, named: "585-03-device-only-the-phone-knows")

        let doorbell = row("192.168.1.60")
        scrollToElement(doorbell)
        requireExists(doorbell, timeout: 5, message: "A device only the Mac knows should be listed")
        XCTAssertTrue(value(doorbell).hasPrefix("Online, from your Mac"), "The Mac's state: \(value(doorbell))")
        XCTAssertTrue(value(doorbell).contains("Last changed 1 hour ago, from your Mac"), "When it changed: \(value(doorbell))")
        XCTAssertNotEqual(doorbell.elementType, .button, "A device only the Mac knows opens nothing: detail would save it")
        captureElement(doorbell, named: "585-04-device-only-the-mac-knows")

        // Device detail says where its status comes from.
        scrollToElement(shared)
        shared.tap()
        let status = ui("deviceDetail_label_status")
        requireExists(status, timeout: 8, message: "Device detail should open")
        XCTAssertTrue(status.label.hasPrefix("Offline, from your Mac, last seen 20 min ago"), "Detail status: \(status.label)")
        let changed = requireExists(ui("deviceDetail_label_macChanged"), message: "Detail says when the device last changed")
        XCTAssertEqual(changed.label, "Last changed 30 min ago, from your Mac")
        let sighting = requireExists(ui("deviceDetail_label_phoneSighting"), message: "Detail shows the phone's own sighting apart")
        captureRegion(from: ui("deviceDetail_label_displayName"), to: sighting, named: "585-05-detail-status-from-your-mac")

        // The Mac leaves: back to the phone's own data, never a frozen state from the Mac.
        openSettings()
        let leaves = app.buttons["settings_button_uitestFakeMacLeaves"]
        scrollToElement(leaves)
        requireExists(leaves, timeout: 5, message: "The UI-test control for the fake Mac leaving").tap()
        openDeviceList()
        XCTAssertTrue(waitForDisappearance(banner, timeout: 30), "The banner goes when the link drops")
        requireExists(shared, timeout: 5, message: "The phone's row stays")
        expectValue(shared, startsWith: "Online, last seen", "The phone's own state after the drop, not the Mac's")
        XCTAssertFalse(value(shared).contains("Seen by this iPhone"), "Only one source again: \(value(shared))")
        XCTAssertFalse(row("192.168.1.60").exists, "The device only the Mac knew is gone")
        captureElement(shared, named: "585-06-fallback-after-the-mac-leaves")
    }

    // MARK: - Helpers

    private func openSettings() {
        requireExists(app.tabBars.buttons["Dashboard"], message: "Dashboard tab should exist").tap()
        app.tabBars.buttons["Dashboard"].tap()
        let settingsButton = app.buttons["dashboard_button_settings"]
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        } else {
            requireExists(app.navigationBars.buttons.firstMatch, message: "A navigation bar button should exist for settings").tap()
        }
        requireExists(app.byID("screen_settings"), timeout: 8, message: "Settings screen should open")
    }

    private func pairWithFakeMac() {
        openSettings()
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

    /// A screenshot of the strip from `top` to `bottom`, full width: the repo is public.
    private func captureRegion(from top: XCUIElement, to bottom: XCUIElement, named name: String) {
        let screenshot = XCUIScreen.main.screenshot().image
        guard let cgImage = screenshot.cgImage else { return }
        let scale = CGFloat(cgImage.height) / screenshot.size.height
        let minY = top.frame.minY - 8, maxY = bottom.frame.maxY + 8
        let rect = CGRect(x: 0, y: minY * scale, width: CGFloat(cgImage.width), height: (maxY - minY) * scale)
        guard let cropped = cgImage.cropping(to: rect) else { return }
        let attachment = XCTAttachment(image: UIImage(cgImage: cropped))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A screenshot of one element only: the repo is public.
    private func captureElement(_ element: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
