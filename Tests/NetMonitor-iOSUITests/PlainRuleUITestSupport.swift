import XCTest

/// Steps the plain-English rule UI tests share (#450, #571, #572).
extension IOSUITestCase {
    func plainRuleElement(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Opens Settings from the dashboard and scrolls to the "Describe a rule…" field.
    func openDescribeRuleField() -> XCUIElement {
        let settings = app.buttons["dashboard_button_settings"]
        // A tab change just before can swallow the first tap; retry once.
        if !settings.waitForExistence(timeout: 5) {
            app.tabBars.buttons["Dashboard"].tap()
        }
        requireExists(settings, timeout: 10, message: "Settings should be reachable").tap()
        let field = plainRuleElement("settings_field_describeRule")
        for _ in 0 ..< 6 where !(field.exists && field.isHittable) {
            app.swipeUp()
        }
        return requireExists(field, timeout: 5, message: "The Describe a rule field should show in Settings")
    }

    /// Types `text` into the describe field and asks for a draft.
    func describeRule(_ text: String) {
        let field = openDescribeRuleField()
        field.tap()
        field.typeText(text)
        requireExists(plainRuleElement("settings_button_createRuleDraft"), message: "Create Draft should show").tap()
    }

    /// Keeps a screenshot cropped to `element`, so no other screen content goes into the evidence.
    func keepCroppedEvidence(_ element: XCUIElement, named name: String) {
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
}
