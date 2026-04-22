import XCTest

@MainActor
final class DNSLookupToolUITests: MacOSUITestCase {

    private func openDNSLookup() {
        openTool(cardID: "tools_card_dns_lookup", sheetElement: "dns_textfield_hostname")
    }

    // MARK: - Element Existence

    func testHostnameFieldExists() {
        openDNSLookup()
        requireExists(app.textFields["dns_textfield_hostname"], message: "Hostname field should exist")
        captureScreenshot(named: "DNSLookup_Screen")
    }

    func testRecordTypePickerExists() {
        openDNSLookup()
        requireExists(app.popUpButtons["dns_picker_type"], message: "Record type picker should exist")
    }

    func testLookupButtonExists() {
        openDNSLookup()
        requireExists(app.buttons["dns_button_lookup"], message: "Lookup button should exist")
    }

    func testCloseButtonExists() {
        openDNSLookup()
        requireExists(app.buttons["dns_button_close"], message: "Close button should exist")
    }

    // MARK: - Input Validation

    func testLookupButtonDisabledWhenHostEmpty() {
        openDNSLookup()
        let lookupButton = requireExists(app.buttons["dns_button_lookup"], message: "Lookup button should exist")
        XCTAssertFalse(lookupButton.isEnabled, "Lookup button should be disabled without hostname")
    }

    func testLookupButtonEnabledAfterTypingHostname() {
        openDNSLookup()
        clearAndTypeText("example.com", into: app.textFields["dns_textfield_hostname"])
        let lookupButton = requireExists(app.buttons["dns_button_lookup"], message: "Lookup button should exist")
        XCTAssertTrue(lookupButton.isEnabled, "Lookup button should be enabled after entering hostname")
    }

    // MARK: - Navigation

    func testCloseButtonDismissesSheet() {
        openDNSLookup()
        app.buttons["dns_button_close"].tap()
        requireExists(
            app.otherElements["tools_card_dns_lookup"],
            message: "Tool card should reappear after closing sheet"
        )
    }

    // MARK: - Lookup Execution

    func testPerformDNSLookup() {
        openDNSLookup()
        clearAndTypeText("example.com", into: app.textFields["dns_textfield_hostname"])
        app.buttons["dns_button_lookup"].tap()

        // Verify real result DATA appears — `dns_section_results` is attached
        // to the ForEach that iterates records, so it only exists when the
        // results array is non-empty.
        let resultsSection = ui("dns_section_results")
        XCTAssertTrue(
            resultsSection.waitForExistence(timeout: 15),
            "DNS lookup should render dns_section_results with live records for example.com"
        )

        let clearButton = app.buttons["dns_button_clear"]
        XCTAssertTrue(
            clearButton.waitForExistence(timeout: 5),
            "Clear button should be available after DNS records are rendered"
        )
        captureScreenshot(named: "DNSLookup_Results")
    }

    func testClearButtonRemovesResults() {
        openDNSLookup()
        clearAndTypeText("example.com", into: app.textFields["dns_textfield_hostname"])
        app.buttons["dns_button_lookup"].tap()

        let resultsSection = ui("dns_section_results")
        XCTAssertTrue(
            resultsSection.waitForExistence(timeout: 15),
            "DNS results section should appear before testing clear"
        )

        let clearButton = app.buttons["dns_button_clear"]
        XCTAssertTrue(clearButton.exists, "Clear button should be present alongside results")
        clearButton.tap()

        XCTAssertTrue(
            waitForDisappearance(clearButton, timeout: 3),
            "Clear button should disappear after clearing results"
        )
        XCTAssertTrue(
            waitForDisappearance(resultsSection, timeout: 3),
            "Results section should disappear after clearing — verifies results were wiped"
        )
    }

    func testRecordTypePickerInteraction() {
        openDNSLookup()
        let picker = requireExists(app.popUpButtons["dns_picker_type"], message: "Record type picker should exist")
        picker.tap()

        let recordTypes = ["AAAA", "MX", "TXT", "CNAME", "NS"]
        for recordType in recordTypes {
            let option = app.menuItems[recordType]
            if option.waitForExistence(timeout: 2) {
                option.tap()
                break
            }
        }
        captureScreenshot(named: "DNSLookup_RecordTypePicked")
    }
}
