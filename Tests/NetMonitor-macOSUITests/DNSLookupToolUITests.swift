import XCTest

@MainActor
final class DNSLookupToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools
        let sidebar = app.descendants(matching: .any)["sidebar_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        // Open DNS Lookup tool
        let card = app.otherElements["tools_card_dns_lookup"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Element Existence

    func testHostnameFieldExists() {
        XCTAssertTrue(app.textFields["dns_textfield_hostname"].waitForExistence(timeout: 3))
    }

    func testRecordTypePickerExists() {
        XCTAssertTrue(app.popUpButtons["dns_picker_type"].waitForExistence(timeout: 3))
    }

    func testLookupButtonExists() {
        XCTAssertTrue(app.buttons["dns_button_lookup"].waitForExistence(timeout: 3))
    }

    func testCloseButtonExists() {
        XCTAssertTrue(app.buttons["dns_button_close"].waitForExistence(timeout: 3))
    }

    // MARK: - Interactions

    func testLookupButtonDisabledWhenHostEmpty() {
        let lookupButton = app.buttons["dns_button_lookup"]
        XCTAssertTrue(lookupButton.waitForExistence(timeout: 3))
        XCTAssertFalse(lookupButton.isEnabled)
    }

    func testLookupButtonEnabledAfterTypingHostname() {
        let hostnameField = app.textFields["dns_textfield_hostname"]
        XCTAssertTrue(hostnameField.waitForExistence(timeout: 3))
        hostnameField.tap()
        hostnameField.typeText("example.com")

        XCTAssertTrue(app.buttons["dns_button_lookup"].isEnabled)
    }

    func testCloseButtonDismissesSheet() {
        app.buttons["dns_button_close"].tap()
        XCTAssertTrue(app.otherElements["tools_card_dns_lookup"].waitForExistence(timeout: 3))
    }

    func testPerformDNSLookup() {
        let hostnameField = app.textFields["dns_textfield_hostname"]
        XCTAssertTrue(hostnameField.waitForExistence(timeout: 3))
        hostnameField.tap()
        hostnameField.typeText("example.com")

        app.buttons["dns_button_lookup"].tap()

        // Wait for results or clear button to appear
        let clearButton = app.buttons["dns_button_clear"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 15))
    }

    func testClearButtonAfterLookup() {
        let hostnameField = app.textFields["dns_textfield_hostname"]
        XCTAssertTrue(hostnameField.waitForExistence(timeout: 3))
        hostnameField.tap()
        hostnameField.typeText("example.com")

        app.buttons["dns_button_lookup"].tap()

        let clearButton = app.buttons["dns_button_clear"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 15))
        clearButton.tap()

        // After clearing, the clear button should disappear
        XCTAssertFalse(clearButton.waitForExistence(timeout: 2))
    }
}
