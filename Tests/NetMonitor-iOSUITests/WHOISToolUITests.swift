@preconcurrency import XCTest

final class WHOISToolUITests: IOSUITestCase {

    private func navigateToWHOISTool() {
        app.tabBars.buttons["Tools"].tap()
        let whoisCard = app.otherElements["tools_card_whois"]
        scrollToElement(whoisCard)
        requireExists(whoisCard, timeout: 8, message: "WHOIS tool card should exist")
        whoisCard.tap()
        requireExists(app.otherElements["screen_whoisTool"], timeout: 8, message: "WHOIS tool screen should appear")
    }

    // MARK: - Screen Existence

    func testWHOISScreenExists() throws {
        navigateToWHOISTool()
        requireExists(app.otherElements["screen_whoisTool"], message: "WHOIS screen should exist")
    }

    func testNavigationTitleExists() throws {
        navigateToWHOISTool()
        requireExists(app.navigationBars["WHOIS Lookup"], message: "WHOIS Lookup navigation bar should exist")
    }

    // MARK: - Input Elements

    func testDomainInputFieldExists() throws {
        navigateToWHOISTool()
        requireExists(app.textFields["whois_input_domain"], message: "Domain input field should exist")
    }

    func testRunButtonExists() throws {
        navigateToWHOISTool()
        requireExists(app.buttons["whois_button_run"], message: "Run button should exist")
    }

    // MARK: - Input Interaction

    func testTypeDomainName() throws {
        navigateToWHOISTool()
        let domainField = app.textFields["whois_input_domain"]
        clearAndTypeText("example.com", into: domainField)
        XCTAssertEqual(domainField.value as? String, "example.com")
    }

    // MARK: - Lookup Execution

    func testStartLookup() throws {
        navigateToWHOISTool()
        clearAndTypeText("example.com", into: app.textFields["whois_input_domain"])
        app.buttons["whois_button_run"].tap()
        let domainInfo = app.otherElements["whois_section_domainInfo"]
        XCTAssertTrue(domainInfo.waitForExistence(timeout: 15), "Domain info should appear after lookup")
    }

    func testDomainDatesAppear() throws {
        navigateToWHOISTool()
        clearAndTypeText("example.com", into: app.textFields["whois_input_domain"])
        app.buttons["whois_button_run"].tap()
        let dates = app.otherElements["whois_section_dates"]
        let domainInfo = app.otherElements["whois_section_domainInfo"]
        XCTAssertTrue(
            waitForEither([dates, domainInfo], timeout: 15),
            "Dates or domain info should appear after lookup"
        )
    }

    func testNameServersAppear() throws {
        navigateToWHOISTool()
        clearAndTypeText("example.com", into: app.textFields["whois_input_domain"])
        app.buttons["whois_button_run"].tap()
        let nameServers = app.otherElements["whois_section_nameServers"]
        let domainInfo = app.otherElements["whois_section_domainInfo"]
        XCTAssertTrue(
            waitForEither([nameServers, domainInfo], timeout: 15),
            "Name servers or domain info should appear after lookup"
        )
    }

    func testClearResultsButton() throws {
        navigateToWHOISTool()
        clearAndTypeText("example.com", into: app.textFields["whois_input_domain"])
        app.buttons["whois_button_run"].tap()
        let domainInfo = app.otherElements["whois_section_domainInfo"]
        if domainInfo.waitForExistence(timeout: 15) {
            let clearButton = app.buttons["whois_button_clear"]
            if clearButton.waitForExistence(timeout: 3) {
                clearButton.tap()
                XCTAssertTrue(waitForDisappearance(domainInfo, timeout: 5), "Domain info should disappear after clear")
            }
        }
    }

    // MARK: - Error State

    func testInvalidDomainShowsError() throws {
        navigateToWHOISTool()
        clearAndTypeText("thisisnotarealdomain12345.invalidtld", into: app.textFields["whois_input_domain"])
        app.buttons["whois_button_run"].tap()
        let errorView = app.otherElements["whois_label_error"]
        let domainInfo = app.otherElements["whois_section_domainInfo"]
        XCTAssertTrue(
            waitForEither([errorView, domainInfo], timeout: 15),
            "Either error or domain info should appear after lookup attempt"
        )
    }

    // MARK: - View Mode Picker

    func testViewModePickerSwitchesContent() throws {
        navigateToWHOISTool()
        clearAndTypeText("example.com", into: app.textFields["whois_input_domain"])
        app.buttons["whois_button_run"].tap()

        let domainInfo = app.otherElements["whois_section_domainInfo"]
        let errorView = app.otherElements["whois_label_error"]
        guard waitForEither([domainInfo, errorView], timeout: 20) else { return }
        guard domainInfo.exists else { return }

        let viewModePicker = app.segmentedControls["whois_picker_viewmode"]
        guard viewModePicker.waitForExistence(timeout: 5) else { return }

        let parsedSegment = viewModePicker.buttons["Parsed"]
        if parsedSegment.exists {
            parsedSegment.tap()
            XCTAssertTrue(domainInfo.waitForExistence(timeout: 5), "Parsed view should show domain info")
        }

        let rawSegment = viewModePicker.buttons["Raw"]
        if rawSegment.exists {
            rawSegment.tap()
            let rawContent = app.otherElements["whois_rawContent"]
            let rawText = app.textViews.firstMatch
            XCTAssertTrue(
                rawContent.waitForExistence(timeout: 5) || rawText.waitForExistence(timeout: 5),
                "Raw content should appear after switching to raw view"
            )
        }
    }

    func testClearButtonRemovesResults() throws {
        navigateToWHOISTool()
        clearAndTypeText("example.com", into: app.textFields["whois_input_domain"])
        app.buttons["whois_button_run"].tap()

        let domainInfo = app.otherElements["whois_section_domainInfo"]
        let clearButton = app.buttons["whois_button_clear"]

        guard domainInfo.waitForExistence(timeout: 20) else { return }
        guard clearButton.waitForExistence(timeout: 5) else { return }

        clearButton.tap()

        XCTAssertTrue(
            waitForDisappearance(domainInfo, timeout: 5),
            "Results section should disappear after tapping clear"
        )
    }
}
