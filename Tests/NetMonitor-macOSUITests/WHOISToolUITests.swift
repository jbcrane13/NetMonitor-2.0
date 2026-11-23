import XCTest

@MainActor
final class WHOISToolUITests: MacOSUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        navigateToSidebar("tools")
        let card = ui("tools_card_whois").firstMatch
        requireExists(card, timeout: 3, message: "WHOIS tool card should exist")
        card.click()
    }

    // MARK: - Element Existence

    func testDomainFieldExists() {
        XCTAssertTrue(app.textFields["whois_textfield_domain"].waitForExistence(timeout: 3))
    }

    func testLookupButtonExists() {
        XCTAssertTrue(app.buttons["whois_button_lookup"].waitForExistence(timeout: 3))
    }

    func testCloseButtonExists() {
        XCTAssertTrue(app.buttons["whois_button_close"].waitForExistence(timeout: 3))
    }

    // MARK: - Interactions

    func testLookupButtonDisabledWhenDomainEmpty() {
        let lookupButton = app.buttons["whois_button_lookup"]
        XCTAssertTrue(lookupButton.waitForExistence(timeout: 3))
        XCTAssertFalse(lookupButton.isEnabled)
    }

    func testLookupButtonEnabledAfterTypingDomain() {
        let domainField = app.textFields["whois_textfield_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 3))
        domainField.click()
        domainField.typeText("example.com")

        XCTAssertTrue(app.buttons["whois_button_lookup"].isEnabled)
    }

    func testCloseButtonDismissesSheet() {
        app.buttons["whois_button_close"].click()
        XCTAssertTrue(waitForDisappearance(app.buttons["whois_button_close"]), "Sheet should close")
        XCTAssertTrue(ui("tools_card_whois").firstMatch.waitForExistence(timeout: 3))
    }

    func testPerformWHOISLookup() {
        let domainField = app.textFields["whois_textfield_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 3))
        domainField.click()
        domainField.typeText("example.com")

        app.buttons["whois_button_lookup"].click()

        // Verify parsed result DATA renders — `whois_picker_viewmode` is gated
        // on `result != nil`, and `whois_section_parsed` is the parsed view
        // container. Either appearing proves the WHOIS service returned data.
        let viewModePicker = app.segmentedControls["whois_picker_viewmode"]
        let parsedSection = app.descendants(matching: .any)["whois_section_parsed"]
        XCTAssertTrue(
            viewModePicker.waitForExistence(timeout: 35)
                || parsedSection.waitForExistence(timeout: 5),
            "WHOIS should render parsed result data for example.com"
        )
        captureScreenshot(named: "WHOIS_Result")
    }

    func testClearButtonAfterLookup() {
        let domainField = app.textFields["whois_textfield_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 3))
        domainField.click()
        domainField.typeText("example.com")

        app.buttons["whois_button_lookup"].click()

        let clearButton = app.buttons["whois_button_clear"]
        XCTAssertTrue(
            clearButton.waitForExistence(timeout: 35),
            "Clear button should only appear once WHOIS returned a result"
        )

        // Verify that result-only elements go with it
        let viewModePicker = app.segmentedControls["whois_picker_viewmode"]
        XCTAssertTrue(
            viewModePicker.exists,
            "View mode picker should be present alongside results"
        )

        clearButton.click()

        XCTAssertFalse(clearButton.waitForExistence(timeout: 2))
        XCTAssertFalse(
            viewModePicker.waitForExistence(timeout: 2),
            "View mode picker should disappear when WHOIS result is cleared"
        )
    }
}
