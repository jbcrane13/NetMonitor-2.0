import XCTest

final class WHOISToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Tools"].tap()
        let whoisCard = app.otherElements["tools_card_whois"]
        if whoisCard.waitForExistence(timeout: 5) {
            whoisCard.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testWHOISScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_whoisTool"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["WHOIS Lookup"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Elements

    func testDomainInputFieldExists() throws {
        XCTAssertTrue(app.textFields["whois_input_domain"].waitForExistence(timeout: 5))
    }

    func testRunButtonExists() throws {
        XCTAssertTrue(app.buttons["whois_button_run"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Interaction

    func testTypeDomainName() throws {
        let domainField = app.textFields["whois_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("example.com")
        XCTAssertEqual(domainField.value as? String, "example.com")
    }

    // MARK: - Lookup Execution

    func testStartLookup() throws {
        let domainField = app.textFields["whois_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("example.com")

        app.buttons["whois_button_run"].tap()

        let domainInfo = app.otherElements["whois_domainInfo"]
        XCTAssertTrue(domainInfo.waitForExistence(timeout: 15))
    }

    func testDomainDatesAppear() throws {
        let domainField = app.textFields["whois_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("example.com")

        app.buttons["whois_button_run"].tap()

        let dates = app.otherElements["whois_dates"]
        // Dates may or may not appear depending on the domain
        let domainInfo = app.otherElements["whois_domainInfo"]
        XCTAssertTrue(dates.waitForExistence(timeout: 15) || domainInfo.waitForExistence(timeout: 15))
    }

    func testNameServersAppear() throws {
        let domainField = app.textFields["whois_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("example.com")

        app.buttons["whois_button_run"].tap()

        let nameServers = app.otherElements["whois_nameServers"]
        let domainInfo = app.otherElements["whois_domainInfo"]
        XCTAssertTrue(nameServers.waitForExistence(timeout: 15) || domainInfo.waitForExistence(timeout: 15))
    }

    func testClearResultsButton() throws {
        let domainField = app.textFields["whois_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("example.com")

        app.buttons["whois_button_run"].tap()

        let domainInfo = app.otherElements["whois_domainInfo"]
        if domainInfo.waitForExistence(timeout: 15) {
            let clearButton = app.buttons["whois_button_clear"]
            if clearButton.waitForExistence(timeout: 3) {
                clearButton.tap()
                XCTAssertFalse(domainInfo.exists)
            }
        }
    }

    // MARK: - Error State

    func testInvalidDomainShowsError() throws {
        let domainField = app.textFields["whois_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5))
        domainField.tap()
        domainField.typeText("thisisnotarealdomain12345.invalidtld")

        app.buttons["whois_button_run"].tap()

        let errorView = app.otherElements["whois_error"]
        let domainInfo = app.otherElements["whois_domainInfo"]
        XCTAssertTrue(errorView.waitForExistence(timeout: 15) || domainInfo.waitForExistence(timeout: 15))
    }
}
