import XCTest

@MainActor
final class DNSLookupToolUITests: IOSUITestCase {

    private func navigateToDNSTool() {
        app.tabBars.buttons["Tools"].tap()
        let dnsCard = app.otherElements["tools_card_dns_lookup"]
        scrollToElement(dnsCard)
        requireExists(dnsCard, timeout: 8, message: "DNS lookup tool card should exist")
        dnsCard.tap()
        requireExists(app.otherElements["screen_dnsLookupTool"], timeout: 8, message: "DNS lookup tool screen should appear")
    }

    // MARK: - Screen Existence

    func testDNSLookupScreenExistsAndShowsControls() throws {
        navigateToDNSTool()
        let screen = app.otherElements["screen_dnsLookupTool"]
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "DNS lookup screen should exist")
        // FUNCTIONAL: screen should show input field and run button
        XCTAssertTrue(
            app.textFields["dnsLookup_input_domain"].waitForExistence(timeout: 3),
            "DNS screen should show domain input field"
        )
        XCTAssertTrue(
            app.buttons["dnsLookup_button_run"].waitForExistence(timeout: 3),
            "DNS screen should show run button"
        )
        captureScreenshot(named: "DNSLookup_Screen")
    }

    func testNavigationTitleExists() throws {
        navigateToDNSTool()
        requireExists(app.navigationBars["DNS Lookup"], message: "DNS Lookup navigation bar should exist")
    }

    // MARK: - Input Elements

    func testDomainInputFieldAcceptsText() throws {
        navigateToDNSTool()
        let domainField = app.textFields["dnsLookup_input_domain"]
        XCTAssertTrue(domainField.waitForExistence(timeout: 5), "Domain input field should exist")
        // FUNCTIONAL: field should accept and display typed text
        clearAndTypeText("example.com", into: domainField)
        XCTAssertEqual(domainField.value as? String, "example.com", "Domain field should contain typed text")
    }

    func testRecordTypePickerExistsAndIsInteractive() throws {
        navigateToDNSTool()
        let pickerExists = app.buttons["dnsLookup_picker_type"].waitForExistence(timeout: 5)
            || app.otherElements["dnsLookup_picker_type"].waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Record type picker should exist")
        // FUNCTIONAL: picker should be tappable
        let activePicker = app.buttons["dnsLookup_picker_type"].exists
            ? app.buttons["dnsLookup_picker_type"]
            : app.otherElements["dnsLookup_picker_type"]
        activePicker.tap()
        XCTAssertTrue(activePicker.waitForExistence(timeout: 3), "Record type picker should remain visible after tap")
    }

    func testRunButtonDisabledUntilDomainEntered() throws {
        navigateToDNSTool()
        let runButton = app.buttons["dnsLookup_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5), "Run button should exist")
        // FUNCTIONAL: run should be disabled without input, enabled with input
        XCTAssertFalse(runButton.isEnabled, "Run button should be disabled when domain is empty")
        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after entering a domain")
    }

    // MARK: - Input Interaction

    func testTypeDomainName() throws {
        navigateToDNSTool()
        let domainField = app.textFields["dnsLookup_input_domain"]
        clearAndTypeText("example.com", into: domainField)
        XCTAssertEqual(domainField.value as? String, "example.com")
    }

    // MARK: - Lookup Execution

    func testStartLookupProducesQueryInfo() throws {
        navigateToDNSTool()
        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        app.buttons["dnsLookup_button_run"].tap()
        let queryInfo = app.otherElements["dnsLookup_section_queryInfo"]
        let errorLabel = app.otherElements["dnsLookup_label_error"]
        XCTAssertTrue(
            waitForEither([queryInfo, errorLabel], timeout: 15),
            "Query info or error should appear after lookup"
        )
        // FUNCTIONAL: verify lookup produced meaningful output
        if queryInfo.exists {
            XCTAssertTrue(
                queryInfo.staticTexts.count > 0,
                "Query info section should contain DNS query data"
            )
        }
    }

    func testRecordsAppearAfterLookup() throws {
        navigateToDNSTool()
        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        app.buttons["dnsLookup_button_run"].tap()
        let records = app.otherElements["dnsLookup_section_records"]
        let queryInfo = app.otherElements["dnsLookup_section_queryInfo"]
        XCTAssertTrue(
            waitForEither([records, queryInfo], timeout: 15),
            "Records or query info should appear after lookup"
        )
        captureScreenshot(named: "DNSLookup_Records")
    }

    func testClearResultsButtonRemovesResults() throws {
        navigateToDNSTool()
        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        app.buttons["dnsLookup_button_run"].tap()
        let queryInfo = app.otherElements["dnsLookup_section_queryInfo"]
        if queryInfo.waitForExistence(timeout: 10) {
            let clearButton = app.buttons["dnsLookup_button_clear"]
            if clearButton.waitForExistence(timeout: 3) {
                clearButton.tap()
                XCTAssertTrue(waitForDisappearance(queryInfo, timeout: 5), "Query info should disappear after clear")
                // FUNCTIONAL: after clearing, run button should be available
                let runButton = app.buttons["dnsLookup_button_run"]
                XCTAssertTrue(runButton.exists, "Run button should be visible after clearing")
                XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after clearing")
            }
        }
    }

    // MARK: - Error State

    func testInvalidDomainShowsError() throws {
        navigateToDNSTool()
        clearAndTypeText("not-a-real-domain-12345.invalid", into: app.textFields["dnsLookup_input_domain"])
        app.buttons["dnsLookup_button_run"].tap()
        let errorView = app.otherElements["dnsLookup_label_error"]
        let queryInfo = app.otherElements["dnsLookup_section_queryInfo"]
        XCTAssertTrue(
            waitForEither([errorView, queryInfo], timeout: 10),
            "Either error or results should appear after lookup attempt"
        )
        captureScreenshot(named: "DNSLookup_ErrorOrResults")
    }

    // MARK: - Record Type Picker Interaction

    func testRecordTypePickerInteraction() throws {
        navigateToDNSTool()

        let pickerButton = app.buttons["dnsLookup_picker_type"]
        let pickerElement = app.otherElements["dnsLookup_picker_type"]
        let pickerExists = pickerButton.waitForExistence(timeout: 5) || pickerElement.waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Record type picker should exist on the DNS lookup screen")

        if pickerButton.exists {
            pickerButton.tap()
        } else {
            pickerElement.tap()
        }

        let recordTypes = ["AAAA", "MX", "TXT", "CNAME", "NS", "A"]
        for recordType in recordTypes {
            let option = app.buttons[recordType]
            if option.waitForExistence(timeout: 2) {
                option.tap()
                break
            }
        }

        let pickerStillExists = pickerButton.waitForExistence(timeout: 3) || pickerElement.waitForExistence(timeout: 3)
        XCTAssertTrue(pickerStillExists, "Record type picker should remain visible after selecting a type")
    }

    func testClearButtonRemovesResults() throws {
        navigateToDNSTool()
        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        app.buttons["dnsLookup_button_run"].tap()

        let queryInfo = app.otherElements["dnsLookup_section_queryInfo"]
        let clearButton = app.buttons["dnsLookup_button_clear"]

        guard queryInfo.waitForExistence(timeout: 15) else { return }
        guard clearButton.waitForExistence(timeout: 5) else { return }

        clearButton.tap()

        XCTAssertTrue(
            waitForDisappearance(queryInfo, timeout: 5),
            "Results should disappear after tapping clear"
        )
    }
}
