import XCTest

/// #571 / #572 user flows with **no saved device rows**. The UI-test scan (`UITEST_FAKE_DEVICES=1`)
/// sees uitest-device-0…4 and, with `UITEST_RULE_SCAN_DEVICES=1`, the printer "office-laser"
/// (192.168.1.30, IPP 631 and 9100 open). The rule parser answers with fixed readings
/// (`UITEST_INSIGHT=answer`).
@MainActor
final class PlainRuleScannedDeviceUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_RULE_SCAN_DEVICES": "1", "UITEST_INSIGHT": "answer"]
    }

    /// Scans from the Map tab and waits for the scan to finish, then goes back to the dashboard.
    /// The map scopes its list to the real Wi-Fi network, so it doesn't list the fixture devices;
    /// the scan still publishes them, on the UI-test network that Settings names devices on.
    private func scan() {
        requireExists(app.tabBars.buttons["Map"], timeout: 10, message: "The Map tab should exist").tap()
        requireExists(plainRuleElement("networkMap_button_scan"), timeout: 10, message: "The map's Scan button should exist").tap()
        // The scan button shows a spinner while it runs.
        let spinner = app.activityIndicators.firstMatch
        _ = spinner.waitForExistence(timeout: 3)
        XCTAssertTrue(waitForDisappearance(spinner, timeout: 20), "The scan should finish")
        // A finished scan can bring up the system's "Enjoying Netmonitor?" rating prompt over the tabs.
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2) {
            notNow.tap()
        }
        app.tabBars.buttons["Dashboard"].tap()
    }

    /// #571: "the printer" names a printer the scan found but nobody opened (its type is inferred
    /// from its open ports), and its port scan opens prefilled.
    func testThePrinterTheScanFoundOpensThePortScanner() {
        scan()
        describeRule("scan web ports on the printer")

        let summary = plainRuleElement("settings_label_ruleDraftSummary")
        requireExists(summary, timeout: 10, message: "A port-scan draft should appear for the scanned printer")
        XCTAssertEqual(summary.label, "Scan web ports on office-laser (192.168.1.30)")
        keepCroppedEvidence(summary, named: "571-ios-scanned-printer-draft")
        plainRuleElement("settings_button_confirmRuleDraft").tap()

        let host = app.textFields["portScanner_input_host"]
        requireExists(host, timeout: 10, message: "The Port Scanner should open")
        XCTAssertEqual(host.value as? String, "192.168.1.30")
        let webPreset = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Web Ports", "Web Ports")).firstMatch
        requireExists(webPreset, timeout: 5, message: "The Web preset should be chosen")
    }

    /// #571 + #572: a target for the scanned printer probes a port the scan found open, and after
    /// Confirm the target is listed.
    func testATargetForTheScannedPrinterIsSavedAndListed() {
        scan()
        describeRule("Tell me if the printer goes offline")

        let summary = plainRuleElement("settings_label_ruleDraftSummary")
        requireExists(summary, timeout: 10, message: "A target draft should appear for the scanned printer")
        XCTAssertEqual(summary.label, "Add a monitoring target for office-laser (192.168.1.30)")
        let probeNote = app.staticTexts.containing(NSPredicate(
            format: "label == %@", "Background checks connect to port 631, which a scan found open on office-laser."
        )).firstMatch
        requireExists(probeNote, timeout: 5, message: "The draft should say which port it probes")
        XCTAssertFalse(plainRuleElement("settings_row_target_192.168.1.30").exists, "Nothing is saved before Confirm")

        plainRuleElement("settings_button_confirmRuleDraft").tap()

        let row = plainRuleElement("settings_row_target_192.168.1.30")
        requireExists(row, timeout: 5, message: "The confirmed target should be listed")
        keepCroppedEvidence(row, named: "571-572-ios-target-listed")
    }

    /// #572: no scan found an open port on uitest-device-3, so a target is refused with why.
    func testATargetForADeviceWithNoKnownOpenPortIsRefused() {
        scan()
        describeRule("Tell me if uitest-device-3 goes offline")

        let message = plainRuleElement("settings_label_ruleMessage")
        requireExists(message, timeout: 10, message: "The draft should be refused with a message")
        XCTAssertEqual(message.label, "uitest-device-3 can't be checked in the background yet: no scan has found an open port on it. "
            + "Scan its ports from its device page, then try again.")
        XCTAssertFalse(plainRuleElement("settings_button_confirmRuleDraft").exists, "Nothing can be confirmed")
        keepCroppedEvidence(message, named: "572-ios-refused")
    }
}
