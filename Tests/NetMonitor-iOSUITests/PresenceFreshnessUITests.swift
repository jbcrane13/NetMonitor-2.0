import XCTest

/// Helpers for the #583 flows below.
/// #583 user flow: the device list says whether each saved device is online, offline or not
/// checked recently, with how long ago it was last seen, and hides past devices behind
/// "Show past devices (N)". The UI-test scan (`UITEST_FAKE_DEVICES=1`) finds uitest-device-0…4;
/// with `UITEST_SCAN_DROP_LAST=1` scans after the first miss uitest-device-4 (192.168.1.14).
/// `UITEST_SCAN_CLOCK=1` steps each scan 10 minutes on, so the grace policy passes without waiting,
/// and presence is shown as of the latest scan on that clock. `UITEST_SEED_PAST_DEVICE=1` adds an
/// offline TV (192.168.1.50) last seen 8 days before. Fixture devices only; screenshots cropped.
@MainActor
class PresenceUITestCase: IOSUITestCase {
    func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func row(_ ip: String) -> XCUIElement {
        ui("deviceList_row_device_\(ip.replacingOccurrences(of: ".", with: "_"))")
    }

    /// Scans from the Map tab and waits for it to finish.
    func scan() {
        requireExists(app.tabBars.buttons["Map"], timeout: 10, message: "The Map tab should exist").tap()
        requireExists(ui("networkMap_button_scan"), timeout: 10, message: "The map's Scan button should exist").tap()
        let spinner = app.activityIndicators.firstMatch
        _ = spinner.waitForExistence(timeout: 3)
        XCTAssertTrue(waitForDisappearance(spinner, timeout: 20), "The scan should finish")
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2) {
            notNow.tap()
        }
    }

    func openDeviceList() {
        app.tabBars.buttons["Dashboard"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        let card = ui("dashboard_card_localDevices")
        scrollToElement(card)
        requireExists(card, timeout: 10, message: "The local devices card should exist").tap()
        requireExists(ui("screen_deviceList"), timeout: 8, message: "The device list should open")
    }

    func value(_ element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    /// Waits until the element's accessibility value starts with `prefix`.
    func expectValue(_ element: XCUIElement, startsWith prefix: String, _ message: String) {
        let predicate = NSPredicate(format: "value BEGINSWITH %@", prefix)
        let met = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: 8), .completed, "\(message): \(value(element))")
    }

}

@MainActor
final class PresenceFreshnessUITests: PresenceUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_SCAN_CLOCK": "1", "UITEST_SCAN_DROP_LAST": "1", "UITEST_SEED_PAST_DEVICE": "1"]
    }

    func testTheListSaysOnlineOrOfflineWithLastSeenAndHidesPastDevices() {
        // Four scans, 10 minutes apart on the scan clock; the last three miss uitest-device-4.
        for _ in 0 ..< 4 {
            scan()
        }
        openDeviceList()

        let online = row("192.168.1.10")
        requireExists(online, timeout: 10, message: "The list should show the answering device")
        expectValue(online, startsWith: "Online, Last seen just now", "The answering device should be online now")
        let offline = row("192.168.1.14")
        scrollToElement(offline)
        requireExists(offline, timeout: 5, message: "The list should show the missing device")
        expectValue(offline, startsWith: "Offline, Last seen", "The missing device should be offline after grace")
        XCTAssertFalse(row("192.168.1.50").exists, "The past TV should be hidden by default")

        let showPast = ui("deviceList_button_showPast")
        scrollToElement(showPast)
        requireExists(showPast, timeout: 5, message: "The list should offer to show past devices")
        XCTAssertEqual(showPast.label, "Show past devices (1)")
        keepCroppedEvidence(offline, named: "583-ios-offline-row")
        keepCroppedEvidence(showPast, named: "583-ios-show-past-devices")

        showPast.tap()
        let past = row("192.168.1.50")
        scrollToElement(past)
        requireExists(past, timeout: 5, message: "Show past devices should list the TV")
        expectValue(past, startsWith: "Offline, Last seen 8 days ago", "The TV was last seen 8 days ago")
        keepCroppedEvidence(past, named: "583-ios-past-device-shown")

        // Back to the top for the online row's evidence.
        app.swipeDown()
        app.swipeDown()
        keepCroppedEvidence(row("192.168.1.10"), named: "583-ios-online-row")
        online.tap()
        let status = ui("deviceDetail_label_status")
        requireExists(status, timeout: 8, message: "Detail should show the status")
        XCTAssertTrue(status.label.hasPrefix("Online, Last seen just now"), "Detail status: \(status.label)")
        keepCroppedEvidence(status, named: "583-ios-detail-status")
    }
}

/// The same network an hour after its only scan (`UITEST_PRESENCE_OFFSET=3600`): every device
/// reads "Not checked recently", never online.
@MainActor
final class PresenceNotCheckedRecentlyUITests: PresenceUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_SCAN_CLOCK": "1", "UITEST_PRESENCE_OFFSET": "3600"]
    }

    func testANetworkNotScannedRecentlyReadsNotCheckedRecently() {
        // The map's note is unit-tested (NetworkMapViewModelTests): the fixture devices aren't on
        // the simulator's subnet, so the map shows none of them.
        scan()
        openDeviceList()
        let device = row("192.168.1.10")
        requireExists(device, timeout: 10, message: "The list should show the device")
        expectValue(device, startsWith: "Not checked recently, Last seen 1 hour ago", "An hour-old scan is not online now")
        XCTAssertFalse(value(device).hasPrefix("Online"), "Never online from an old scan: \(value(device))")
        keepCroppedEvidence(device, named: "583-ios-not-checked-recently-row")
    }
}
