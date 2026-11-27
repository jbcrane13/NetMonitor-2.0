import XCTest

/// #628 user flow: a scan the network path changed under saves nothing, and its one replacement
/// saves the devices. The UI-test scan (`UITEST_FAKE_DEVICES=1`) finds uitest-device-0…4, which the
/// device list shows as found until a scan saves them. `UITEST_SCAN_PATH_CHANGE=1`
/// simulates a path change while every scan but a replacement runs, and holds the replacement 30 s.
/// `UITEST_SCAN_CLOCK=1` stamps the saved scan on 2026-11-20, so Last Seen proves the row came from
/// the replacement's reconcile.
@MainActor
final class ScanPathChangeUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_SCAN_CLOCK": "1", "UITEST_SCAN_PATH_CHANGE": "1"]
    }

    private func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The scan clock's day (2026-11-20), formatted as detail formats it.
    private var scanDay: String {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 8)) ?? .distantPast
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    private func value(_ element: XCUIElement) -> String {
        element.value as? String ?? ""
    }

    func testAScanDroppedByAPathChangeSavesNothingAndItsReplacementSaves() {
        // A scan from the Map tab: the path changes while it runs, so it's dropped.
        requireExists(app.tabBars.buttons["Map"], timeout: 10, message: "The Map tab should exist").tap()
        let scanButton = ui("networkMap_button_scan")
        requireExists(scanButton, timeout: 10, message: "The map's Scan button should exist")
        if scanButton.isEnabled {
            scanButton.tap()
        }
        app.tabBars.buttons["Dashboard"].tap()
        let card = ui("dashboard_card_localDevices")
        scrollToElement(card)
        requireExists(card, timeout: 10, message: "The local devices card should exist").tap()

        // Nothing was saved: the device list shows it only as found by the scan.
        let row = ui("deviceList_row_device_192_168_1_10")
        requireExists(row, timeout: 5, message: "The device list should show 192.168.1.10")
        // A found-only row says "found" ("Found in this scan", or "Not checked recently · found …").
        XCTAssertTrue(value(row).localizedCaseInsensitiveContains("found"), "The dropped scan shouldn't save the device: \(value(row))")
        keepCroppedEvidence(row, named: "628-ios-1-dropped-not-saved")

        // The replacement saves it.
        let saved = NSPredicate(format: "NOT (value CONTAINS[c] %@)", "found")
        let expectation = XCTNSPredicateExpectation(predicate: saved, object: row)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 60), .completed, "The replacement should save it: \(value(row))")
        keepCroppedEvidence(row, named: "628-ios-2-replacement-saved")

        row.tap()
        requireExists(ui("screen_deviceDetail"), timeout: 8, message: "Detail should open")
        let lastSeen = ui("deviceDetail_row_lastSeen")
        scrollToElement(lastSeen)
        let text = app.staticTexts.matching(identifier: "deviceDetail_row_lastSeen")
            .matching(NSPredicate(format: "label != %@", "Last Seen")).firstMatch
        requireExists(text, timeout: 5, message: "Last Seen should have a value")
        XCTAssertTrue(text.label.hasPrefix(scanDay), "The row should come from the replacement's reconcile: \(text.label)")
        keepCroppedEvidence(text, named: "628-ios-3-saved-last-seen")
    }
}
