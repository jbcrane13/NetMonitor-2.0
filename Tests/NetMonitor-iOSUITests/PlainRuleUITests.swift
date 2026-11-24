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

    private func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func openDescribeField() -> XCUIElement {
        requireExists(app.buttons["dashboard_button_settings"], timeout: 10, message: "Settings should be reachable").tap()
        let field = ui("rules_field_describe")
        for _ in 0 ..< 6 where !(field.exists && field.isHittable) {
            app.swipeUp()
        }
        return requireExists(field, timeout: 5, message: "The Describe a rule field should show in Settings")
    }

    /// Keeps a screenshot cropped to `element`, so no other screen content goes into the evidence.
    private func keep(_ element: XCUIElement, named name: String) {
        let image = app.screenshot().image
        let frame = element.frame.insetBy(dx: -8, dy: -8)
        let pixels = CGRect(x: frame.minX * image.scale, y: frame.minY * image.scale,
                            width: frame.width * image.scale, height: frame.height * image.scale)
        guard let cropped = image.cgImage?.cropping(to: pixels) else {
            XCTFail("Could not crop \(name)")
            return
        }
        let attachment = XCTAttachment(image: UIImage(cgImage: cropped, scale: image.scale, orientation: .up))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testScanWebPortsOnThePrinterOpensThePortScannerPrefilled() {
        let field = openDescribeField()
        field.tap()
        field.typeText("scan web ports on the printer")
        requireExists(ui("rules_button_parse"), message: "Create Draft should show").tap()

        let summary = ui("rules_draft_summary")
        requireExists(summary, timeout: 10, message: "A port-scan draft should appear")
        XCTAssertEqual(summary.label, "Scan web ports on uitest-printer (192.168.77.20)")
        XCTAssertTrue(ui("rules_draft_marker").exists, "The draft should be marked as generated")
        keep(summary, named: "450-ios-draft")

        requireExists(ui("rules_button_confirm"), message: "Open Port Scanner should show").tap()

        let host = app.textFields["portScanner_input_host"]
        requireExists(host, timeout: 10, message: "The Port Scanner should open")
        XCTAssertEqual(host.value as? String, "192.168.77.20", "The scanner should be prefilled with the printer's address")
        // The screen's identifier is stamped over the picker's, so find the picker by its choice.
        let webPreset = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Web Ports", "Web Ports")).firstMatch
        requireExists(webPreset, timeout: 5, message: "The port range picker should show the Web preset")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Common Ports")).firstMatch.exists,
                       "The default Common preset should not be chosen")
        let screen = ui("screen_portScannerTool")
        keep(screen.exists ? screen : host, named: "450-ios-port-scanner")
    }

    func testNonsenseGivesTheMessageAndNoDraft() {
        let field = openDescribeField()
        field.tap()
        field.typeText("what's the weather")
        requireExists(ui("rules_button_parse"), message: "Create Draft should show").tap()

        let message = ui("rules_draft_message")
        requireExists(message, timeout: 10, message: "Unsupported input should give a message")
        XCTAssertTrue(message.label.hasPrefix("I can create alerts for a device going offline"), "Message: \(message.label)")
        XCTAssertFalse(ui("rules_button_confirm").exists, "Nothing can be confirmed")
        keep(message, named: "450-ios-unsupported")
    }

    func testTheNASExampleDraftsAMonitoringTargetSavedOnlyOnConfirm() {
        let field = openDescribeField()
        field.tap()
        field.typeText("Tell me if the NAS is down for more than five minutes")
        requireExists(ui("rules_button_parse"), message: "Create Draft should show").tap()

        let summary = ui("rules_draft_summary")
        requireExists(summary, timeout: 10, message: "A target draft should appear")
        XCTAssertEqual(summary.label, "Add a monitoring target for uitest-nas (192.168.77.40)")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "It can't time 5 minutes.")).firstMatch.exists,
                      "The draft should say iOS can't time the five minutes")
        XCTAssertFalse(ui("settings_row_target_192.168.77.40").exists, "Nothing is saved before Confirm")

        ui("rules_button_confirm").tap()
        requireExists(ui("settings_row_target_192.168.77.40"), timeout: 5, message: "The confirmed target should be listed")
    }
}
