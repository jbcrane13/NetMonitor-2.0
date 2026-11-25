import XCTest

/// #450: a rule typed in plain English in Settings › Monitoring Targets. The rule parser answers
/// with the real model's recorded readings (`UITEST_INSIGHT=answer`), and a printer and a NAS
/// are seeded on the UI-test network (`UITEST_SEED_RULE_DEVICES=1`). `UITEST_FAKE_DEVICES=1`
/// makes that the network the app is on: a rule can only name the current network's devices.
@MainActor
final class PlainRuleUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_INSIGHT": "answer", "UITEST_SEED_RULE_DEVICES": "1", "UITEST_FAKE_DEVICES": "1"]
    }

    func testScanWebPortsOnThePrinterOpensThePortScannerPrefilled() {
        let field = openDescribeRuleField()
        field.tap()
        field.typeText("scan web ports on the printer")
        requireExists(plainRuleElement("settings_button_createRuleDraft"), message: "Create Draft should show").tap()

        let summary = plainRuleElement("settings_label_ruleDraftSummary")
        requireExists(summary, timeout: 10, message: "A port-scan draft should appear")
        XCTAssertEqual(summary.label, "Scan web ports on uitest-printer (192.168.77.20)")
        XCTAssertTrue(plainRuleElement("settings_label_ruleDraftMarker").exists, "The draft should be marked as generated")
        keepCroppedEvidence(summary, named: "450-ios-draft")

        requireExists(plainRuleElement("settings_button_confirmRuleDraft"), message: "Open Port Scanner should show").tap()

        let host = app.textFields["portScanner_input_host"]
        requireExists(host, timeout: 10, message: "The Port Scanner should open")
        XCTAssertEqual(host.value as? String, "192.168.77.20", "The scanner should be prefilled with the printer's address")
        // The screen's identifier is stamped over the picker's, so find the picker by its choice.
        let webPreset = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Web Ports", "Web Ports")).firstMatch
        requireExists(webPreset, timeout: 5, message: "The port range picker should show the Web preset")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Common Ports")).firstMatch.exists,
                       "The default Common preset should not be chosen")
        let screen = plainRuleElement("screen_portScannerTool")
        keepCroppedEvidence(screen.exists ? screen : host, named: "450-ios-port-scanner")
    }

    func testNonsenseGivesTheMessageAndNoDraft() {
        let field = openDescribeRuleField()
        field.tap()
        field.typeText("what's the weather")
        requireExists(plainRuleElement("settings_button_createRuleDraft"), message: "Create Draft should show").tap()

        let message = plainRuleElement("settings_label_ruleMessage")
        requireExists(message, timeout: 10, message: "Unsupported input should give a message")
        XCTAssertTrue(message.label.hasPrefix("I can create alerts for a device going offline"), "Message: \(message.label)")
        XCTAssertFalse(plainRuleElement("settings_button_confirmRuleDraft").exists, "Nothing can be confirmed")
        keepCroppedEvidence(message, named: "450-ios-unsupported")
    }

    func testTheNASExampleDraftsAMonitoringTargetSavedOnlyOnConfirm() {
        let field = openDescribeRuleField()
        field.tap()
        field.typeText("Tell me if the NAS is down for more than five minutes")
        requireExists(plainRuleElement("settings_button_createRuleDraft"), message: "Create Draft should show").tap()

        let summary = plainRuleElement("settings_label_ruleDraftSummary")
        requireExists(summary, timeout: 10, message: "A target draft should appear")
        XCTAssertEqual(summary.label, "Add a monitoring target for uitest-nas (192.168.77.40)")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "It can't time 5 minutes.")).firstMatch.exists,
                      "The draft should say iOS can't time the five minutes")
        XCTAssertFalse(plainRuleElement("settings_row_target_192.168.77.40").exists, "Nothing is saved before Confirm")

        plainRuleElement("settings_button_confirmRuleDraft").tap()
        requireExists(plainRuleElement("settings_row_target_192.168.77.40"), timeout: 5, message: "The confirmed target should be listed")
    }
}
