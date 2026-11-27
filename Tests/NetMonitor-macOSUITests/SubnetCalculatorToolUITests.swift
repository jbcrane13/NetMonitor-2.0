import XCTest

@MainActor
final class SubnetCalculatorToolUITests: MacOSUITestCase {

    // MARK: - Helpers

    private func openSubnetCalculator() {
        navigateToSidebar("tools")
        let card = ui("tools_card_subnet_calculator").firstMatch
        requireExists(card, timeout: 5, message: "Subnet Calculator tool card should exist in the Tools grid").click()
    }

    // MARK: - Tests

    func testSubnetCalculatorCardExistsInToolsGrid() {
        navigateToSidebar("tools")
        let card = ui("tools_card_subnet_calculator").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Subnet Calculator tool card should exist in the Tools grid")
    }

    func testValidCIDRShowsResults() {
        openSubnetCalculator()

        let input = app.textFields["subnetCalc_textfield_cidr"]
        guard input.waitForExistence(timeout: 5) else {
            XCTFail("CIDR input field not found")
            return
        }

        input.click()
        input.typeText("192.168.1.0/24")
        app.buttons["subnetCalc_button_calculate"].click()

        XCTAssertTrue(
            ui("subnetCalc_section_results").firstMatch.waitForExistence(timeout: 5),
            "Results section should appear after valid CIDR calculation"
        )
    }

    func testInvalidCIDRShowsError() {
        openSubnetCalculator()

        let input = app.textFields["subnetCalc_textfield_cidr"]
        guard input.waitForExistence(timeout: 5) else {
            XCTFail("CIDR input field not found")
            return
        }

        input.click()
        input.typeText("192.168.1.0/99")
        app.buttons["subnetCalc_button_calculate"].click()

        XCTAssertTrue(
            ui("subnetCalc_card_error").firstMatch.waitForExistence(timeout: 5),
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
            ui("subnetCalc_section_results").firstMatch.waitForExistence(timeout: 5),
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

        let results = ui("subnetCalc_section_results").firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 5), "Clicking an example should produce results")

        let clearButton = app.buttons["subnetCalc_button_clear"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5), "Clear button should appear after results")
        clearButton.click()

        XCTAssertTrue(waitForDisappearance(results), "Results section should disappear after clearing")
    }
}
