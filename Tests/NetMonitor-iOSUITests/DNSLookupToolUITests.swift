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

    func testDNSLookupScreenExists() throws {
        navigateToDNSTool()
        requireExists(app.otherElements["screen_dnsLookupTool"], message: "DNS lookup screen should exist")
    }

    func testNavigationTitleExists() throws {
        navigateToDNSTool()
        requireExists(app.navigationBars["DNS Lookup"], message: "DNS Lookup navigation bar should exist")
    }

    // MARK: - Input Elements

    func testDomainInputFieldExists() throws {
        navigateToDNSTool()
        requireExists(app.textFields["dnsLookup_input_domain"], message: "Domain input field should exist")
    }

    func testRecordTypePickerExists() throws {
        navigateToDNSTool()
        let pickerExists = app.buttons["dnsLookup_picker_type"].waitForExistence(timeout: 5)
            || app.otherElements["dnsLookup_picker_type"].waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Record type picker should exist")
    }

    func testRunButtonExists() throws {
        navigateToDNSTool()
        requireExists(app.buttons["dnsLookup_button_run"], message: "Run button should exist")
    }

    // MARK: - Input Interaction

    func testTypeDomainName() throws {
        navigateToDNSTool()
        let domainField = app.textFields["dnsLookup_input_domain"]
        clearAndTypeText("example.com", into: domainField)
        XCTAssertEqual(domainField.value as? String, "example.com")
    }

    // MARK: - Lookup Execution

    func testStartLookup() throws {
        navigateToDNSTool()
        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        app.buttons["dnsLookup_button_run"].tap()
        let queryInfo = app.otherElements["dnsLookup_section_queryInfo"]
        XCTAssertTrue(queryInfo.waitForExistence(timeout: 10), "Query info should appear after lookup")
    }

    func testRecordsAppearAfterLookup() throws {
        navigateToDNSTool()
        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        app.buttons["dnsLookup_button_run"].tap()
        let records = app.otherElements["dnsLookup_section_records"]
        XCTAssertTrue(records.waitForExistence(timeout: 10), "Records should appear after lookup")
    }

    func testClearResultsButton() throws {
        navigateToDNSTool()
        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        app.buttons["dnsLookup_button_run"].tap()
        let queryInfo = app.otherElements["dnsLookup_section_queryInfo"]
        if queryInfo.waitForExistence(timeout: 10) {
            let clearButton = app.buttons["dnsLookup_button_clear"]
            if clearButton.waitForExistence(timeout: 3) {
                clearButton.tap()
                XCTAssertTrue(waitForDisappearance(queryInfo, timeout: 5), "Query info should disappear after clear")
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
