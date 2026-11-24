import XCTest

/// #582 user flow: every scan updates the saved device rows. The UI-test scan
/// (`UITEST_FAKE_DEVICES=1`) finds uitest-device-0…4; with `UITEST_SCAN_DROP_LAST=1` scans after the
/// first no longer find uitest-device-4 (192.168.1.14). `UITEST_SCAN_CLOCK=1` stamps the first
/// scan 08:00 on 2026-11-20 and each later one 10 minutes on, so the grace policy (3 missed scans
/// and 15 minutes) passes without waiting.
@MainActor
final class SavedDevicePresenceUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_SCAN_CLOCK": "1", "UITEST_SCAN_DROP_LAST": "1"]
    }

    private func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Scans from the Map tab and waits for it to finish.
    private func scan() {
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

    /// Opens a device's detail from the dashboard's device list.
    private func openDetail(_ ip: String) {
        app.tabBars.buttons["Dashboard"].tap()
        let card = ui("dashboard_card_localDevices")
        scrollToElement(card)
        requireExists(card, timeout: 10, message: "The local devices card should exist").tap()
        let row = ui("deviceList_row_device_\(ip.replacingOccurrences(of: ".", with: "_"))")
        requireExists(row, timeout: 8, message: "The list should show \(ip)").tap()
        requireExists(ui("screen_deviceDetail"), timeout: 8, message: "Detail should open for \(ip)")
    }

    /// The Last Seen row's value, scrolled into view. The row's label and value are two texts
    /// with the row's identifier.
    private func lastSeen() -> (element: XCUIElement, value: String) {
        let row = ui("deviceDetail_row_lastSeen")
        scrollToElement(row)
        requireExists(row, timeout: 5, message: "Detail should show Last Seen")
        let value = app.staticTexts.matching(identifier: "deviceDetail_row_lastSeen")
            .matching(NSPredicate(format: "label != %@", "Last Seen")).firstMatch
        requireExists(value, timeout: 5, message: "Last Seen should have a value")
        return (value, value.label)
    }

    private func date(_ text: String) -> Date? {
        try? Date(text, strategy: Date.FormatStyle(date: .abbreviated, time: .shortened))
    }

    private func backToDashboard() {
        app.tabBars.buttons["Dashboard"].tap()
        app.tabBars.buttons["Dashboard"].tap()
    }

    /// The scan clock's day (2026-11-20), formatted as detail formats it.
    private var scanDay: String {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 8)) ?? .distantPast
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    func testAScanUpdatesLastSeenAndAMissingDeviceGoesOfflineAfterGrace() {
        scan()
        openDetail("192.168.1.10")
        // Stamped by the scan's clock (2026-11-20), not the day the row was created.
        let first = lastSeen()
        XCTAssertTrue(first.value.hasPrefix(scanDay), "Last Seen should be the scan's time: \(first.value)")
        XCTAssertTrue(ui("deviceDetail_label_status").label.contains("Online"), "Status: \(ui("deviceDetail_label_status").label)")
        keepCroppedEvidence(first.element, named: "582-ios-last-seen-first-scan")
        backToDashboard()

        // Three more scans, each 10 minutes on along the scan clock, none finding uitest-device-4.
        for _ in 0 ..< 3 {
            scan()
        }

        openDetail("192.168.1.10")
        let latest = lastSeen()
        if let firstDate = date(first.value), let latestDate = date(latest.value) {
            // At least the three scans' 30 minutes; the app may scan on its own too (the dashboard on appear).
            XCTAssertGreaterThanOrEqual(latestDate.timeIntervalSince(firstDate), 30 * 60, "Last Seen should follow the latest scan: \(latest.value)")
        } else {
            XCTFail("Unreadable Last Seen: \(first.value) / \(latest.value)")
        }
        keepCroppedEvidence(latest.element, named: "582-ios-last-seen-latest-scan")
        backToDashboard()

        openDetail("192.168.1.14")
        let status = ui("deviceDetail_label_status")
        requireExists(status, timeout: 5, message: "Detail should show the status")
        XCTAssertTrue(status.label.contains("Offline"), "The missing device should be offline after grace: \(status.label)")
        keepCroppedEvidence(status, named: "582-ios-offline-after-grace-status")
        let missing = lastSeen()
        if let missingDate = date(missing.value), let latestDate = date(latest.value) {
            XCTAssertLessThan(missingDate, latestDate, "Last Seen should stay at its last answer: \(missing.value)")
        } else {
            XCTFail("Unreadable Last Seen: \(missing.value)")
        }
        keepCroppedEvidence(missing.element, named: "582-ios-offline-after-grace-last-seen")
    }
}
