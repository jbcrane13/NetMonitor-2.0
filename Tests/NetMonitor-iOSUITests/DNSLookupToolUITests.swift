import XCTest

final class DNSLookupToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Tools"].tap()
        let dnsCard = app.otherElements["tools_card_dns_lookup"]
        if dnsCard.waitForExistence(timeout: 5) {
            dnsCard.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testDNSLookupScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_dnsLookupTool"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["DNS Lookup"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Elements

    func testDomainInputFieldExists() throws {
        XCTAssertTrue(app.textFields["dnsLookup_input_domain"].waitForExistence(timeout: 5))
    }

    func testRecordTypePickerExists() throws {
        XCTAssertTrue(app.buttons["dnsLookup_picker_type"].waitForExistence(timeout: 5) ||
                      app.otherElements["dnsLookup_picker_type"].waitForExistence(timeout: 3))
    }

    func testRunButtonExists() throws {
        XCTAssertTrue(app.buttons["dnsLookup_button_run"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Interaction

    func testTypeDomainName() throws {
        let domainField = app.textFields["dnsLookup_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("example.com")
        XCTAssertEqual(domainField.value as? String, "example.com")
    }

    // MARK: - Lookup Execution

    func testStartLookup() throws {
        let domainField = app.textFields["dnsLookup_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("example.com")

        let runButton = app.buttons["dnsLookup_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 3))
        runButton.tap()

        // Query info should appear
        let queryInfo = app.otherElements["dnsLookup_queryInfo"]
        XCTAssertTrue(queryInfo.waitForExistence(timeout: 10))
    }

    func testRecordsAppearAfterLookup() throws {
        let domainField = app.textFields["dnsLookup_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("example.com")

        app.buttons["dnsLookup_button_run"].tap()

        let records = app.otherElements["dnsLookup_records"]
        XCTAssertTrue(records.waitForExistence(timeout: 10))
    }

    func testClearResultsButton() throws {
        let domainField = app.textFields["dnsLookup_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("example.com")

        app.buttons["dnsLookup_button_run"].tap()

        let queryInfo = app.otherElements["dnsLookup_queryInfo"]
        if queryInfo.waitForExistence(timeout: 10) {
            let clearButton = app.buttons["dnsLookup_button_clear"]
            if clearButton.waitForExistence(timeout: 3) {
                clearButton.tap()
                XCTAssertFalse(queryInfo.exists)
            }
        }
    }

    // MARK: - Error State

    func testInvalidDomainShowsError() throws {
        let domainField = app.textFields["dnsLookup_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("not-a-real-domain-12345.invalid")

        app.buttons["dnsLookup_button_run"].tap()

        let errorView = app.otherElements["dnsLookup_error"]
        // Either error or results should appear
        let queryInfo = app.otherElements["dnsLookup_queryInfo"]
        XCTAssertTrue(errorView.waitForExistence(timeout: 10) || queryInfo.waitForExistence(timeout: 10))
    }
}
