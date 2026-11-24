import XCTest

/// #571 / #572 user flows with **no saved device rows**: the UI-test scan (`UITEST_FAKE_DEVICES=1`)
/// sees uitest-device-0…4, and the rule parser answers with fixed readings (`UITEST_INSIGHT=answer`).
@MainActor
final class PlainRuleScannedDeviceUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_INSIGHT": "answer"]
    }

    private func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Scans from the Map tab, then opens the dashboard's Settings. The map scopes its list to the
    /// real Wi-Fi network, so it doesn't list the fixture devices; the scan still publishes them,
    /// on the UI-test network, which is the network Settings names devices on.
    private func scanThenOpenDescribeField() -> XCUIElement {
        requireExists(app.tabBars.buttons["Map"], timeout: 10, message: "The Map tab should exist").tap()
        requireExists(ui("networkMap_button_scan"), timeout: 10, message: "The map's Scan button should exist").tap()
        // The fake scan holds 300 ms before publishing; give it time to finish.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "fake scan finishes")], timeout: 3)
        let settings = app.buttons["dashboard_button_settings"]
        app.tabBars.buttons["Dashboard"].tap()
        // A tab tap right after the map's scan can miss; retry once.
        if !settings.waitForExistence(timeout: 5) {
            app.tabBars.buttons["Dashboard"].tap()
        }
        requireExists(settings, timeout: 10, message: "Settings should be reachable").tap()
        let field = ui("settings_field_describeRule")
        for _ in 0 ..< 6 where !(field.exists && field.isHittable) {
            app.swipeUp()
        }
        return requireExists(field, timeout: 5, message: "The Describe a rule field should show in Settings")
    }

    private func describe(_ text: String) {
        let field = scanThenOpenDescribeField()
        field.tap()
        field.typeText(text)
        requireExists(ui("settings_button_createRuleDraft"), message: "Create Draft should show").tap()
    }

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

    /// #571: a device the scan found but nobody opened is named, and its port scan opens prefilled.
    func testAScannedDeviceWithNoSavedRowOpensThePortScanner() {
        describe("scan web ports on uitest-device-2")

        let summary = ui("settings_label_ruleDraftSummary")
        requireExists(summary, timeout: 10, message: "A port-scan draft should appear for the scanned device")
        XCTAssertEqual(summary.label, "Scan web ports on uitest-device-2 (192.168.1.12)")
        keep(summary, named: "571-ios-scanned-device-draft")
        ui("settings_button_confirmRuleDraft").tap()

        let host = app.textFields["portScanner_input_host"]
        requireExists(host, timeout: 10, message: "The Port Scanner should open")
        XCTAssertEqual(host.value as? String, "192.168.1.12")
        let webPreset = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Web Ports", "Web Ports")).firstMatch
        requireExists(webPreset, timeout: 5, message: "The Web preset should be chosen")
    }

    /// #572: no scan found an open port on uitest-device-3, so a target is refused with why.
    func testATargetForADeviceWithNoKnownOpenPortIsRefused() {
        describe("Tell me if uitest-device-3 goes offline")

        let message = ui("settings_label_ruleMessage")
        requireExists(message, timeout: 10, message: "The draft should be refused with a message")
        XCTAssertEqual(message.label, "uitest-device-3 can't be checked in the background yet: no scan has found an open port on it. "
            + "Scan its ports from its device page, then try again.")
        XCTAssertFalse(ui("settings_button_confirmRuleDraft").exists, "Nothing can be confirmed")
        keep(message, named: "572-ios-refused")
    }
}
