@preconcurrency import XCTest

final class SubnetCalculatorToolUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Helpers

    private func openSubnetCalculator() {
        // Navigate to Tools and open Subnet Calculator card
        let card = app.buttons["tools_card_subnet_calculator"]
        if card.waitForExistence(timeout: 5) {
            card.click()
        }
    }

    // MARK: - Tests

    func testSubnetCalculatorCardExistsInToolsGrid() {
        let card = app.buttons["tools_card_subnet_calculator"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Subnet Calculator tool card should exist in the Tools grid")
    }

    func testValidCIDRShowsResults() {
        openSubnetCalculator()

        let input = app.textFields["subnetCalc_input_cidr"]
        guard input.waitForExistence(timeout: 5) else {
            XCTFail("CIDR input field not found")
            return
        }

        input.click()
        input.typeText("192.168.1.0/24")
        app.buttons["subnetCalc_button_calculate"].click()

        XCTAssertTrue(
            app.staticTexts["subnetCalc_section_results"].waitForExistence(timeout: 5),
            "Results section should appear after valid CIDR calculation"
        )
    }

    func testInvalidCIDRShowsError() {
        openSubnetCalculator()

        let input = app.textFields["subnetCalc_input_cidr"]
        guard input.waitForExistence(timeout: 5) else {
            XCTFail("CIDR input field not found")
            return
        }

        input.click()
        input.typeText("192.168.1.0/99")
        app.buttons["subnetCalc_button_calculate"].click()

        XCTAssertTrue(
            app.staticTexts["subnetCalc_card_error"].waitForExistence(timeout: 5),
            "Error card should appear for invalid CIDR"
        )
    }

    func testExampleButtonCalculates() {
        openSubnetCalculator()

        let example = app.buttons["subnetCalc_example_192.168.1.0_24"]
        guard example.waitForExistence(timeout: 5) else {
            XCTFail("Example button not found")
            return
        }

        example.click()

        XCTAssertTrue(
            app.staticTexts["subnetCalc_section_results"].waitForExistence(timeout: 5),
            "Clicking an example should produce results"
        )
    }

    func testClearButtonResetsState() {
        openSubnetCalculator()

        let example = app.buttons["subnetCalc_example_192.168.1.0_24"]
        guard example.waitForExistence(timeout: 5) else {
            XCTFail("Example button not found")
            return
        }
        example.click()

        _ = app.staticTexts["subnetCalc_section_results"].waitForExistence(timeout: 5)

        let clearButton = app.buttons["subnetCalc_button_clear"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5), "Clear button should appear after results")
        clearButton.click()

        XCTAssertFalse(
            app.staticTexts["subnetCalc_section_results"].exists,
            "Results section should disappear after clearing"
        )
    }
}
