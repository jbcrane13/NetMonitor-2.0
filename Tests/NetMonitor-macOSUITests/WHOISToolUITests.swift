import XCTest

@MainActor
@MainActor
final class WHOISToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools
        let sidebar = app.descendants(matching: .any)["sidebar_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        // Open WHOIS tool
        let card = app.otherElements["tools_card_whois"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

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
        domainField.tap()
        domainField.typeText("example.com")

        XCTAssertTrue(app.buttons["whois_button_lookup"].isEnabled)
    }

    func testCloseButtonDismissesSheet() {
        app.buttons["whois_button_close"].tap()
        XCTAssertTrue(app.otherElements["tools_card_whois"].waitForExistence(timeout: 3))
    }

    func testPerformWHOISLookup() {
        let domainField = app.textFields["whois_textfield_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 3))
        domainField.tap()
        domainField.typeText("example.com")

        app.buttons["whois_button_lookup"].tap()

        // Wait for results - view mode picker appears when parsed info is available
        let viewModePicker = app.segmentedControls["whois_picker_viewmode"]
        XCTAssertTrue(viewModePicker.waitForExistence(timeout: 35))
    }

    func testClearButtonAfterLookup() {
        let domainField = app.textFields["whois_textfield_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 3))
        domainField.tap()
        domainField.typeText("example.com")

        app.buttons["whois_button_lookup"].tap()

        let clearButton = app.buttons["whois_button_clear"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 35))
        clearButton.tap()

        XCTAssertFalse(clearButton.waitForExistence(timeout: 2))
    }
}
