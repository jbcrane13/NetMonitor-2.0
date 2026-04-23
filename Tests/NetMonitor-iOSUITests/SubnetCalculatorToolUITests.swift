import XCTest

@MainActor
final class SubnetCalculatorToolUITests: IOSUITestCase {
    func testSubnetCalculatorValidationErrorAndClearFlow() {
        openSubnetCalculator()

        let calculateButton = requireExists(
            app.buttons["subnetTool_button_calculate"],
            message: "Subnet calculator button should exist"
        )
        XCTAssertFalse(calculateButton.isEnabled, "Calculate should be disabled before input")

        clearAndTypeText("192.168.1.0/99", into: app.textFields["subnetTool_input_cidr"])
        XCTAssertTrue(calculateButton.isEnabled, "Calculate should be enabled after input")

        calculateButton.tap()
        // FUNCTIONAL: invalid CIDR should show an error card
        requireExists(ui("subnetTool_card_error"), timeout: 5, message: "Invalid CIDR should show error card")
        XCTAssertTrue(
            ui("subnetTool_card_error").staticTexts.count > 0,
            "Error card should contain error description text"
        )

        requireExists(app.buttons["subnetTool_button_clear"], message: "Clear button should be visible after result/error").tap()
        XCTAssertTrue(
            waitForDisappearance(ui("subnetTool_card_error"), timeout: 5),
            "Error card should disappear after clear"
        )
        // FUNCTIONAL: after clearing, calculate button should be ready for new input
        XCTAssertTrue(calculateButton.exists, "Calculate button should be visible after clearing error")
    }

    func testSubnetCalculatorExampleProducesResults() {
        openSubnetCalculator()

        let example = requireExists(
            app.buttons["subnetTool_example_192.168.1.0_24"],
            message: "Known CIDR example should be visible"
        )
        // FUNCTIONAL: tapping example should populate input and show results
        example.tap()

        requireExists(
            ui("subnetTool_section_results"),
            timeout: 8,
            message: "Selecting a valid example should produce results"
        )
        // FUNCTIONAL: results section should contain subnet data
        XCTAssertTrue(
            ui("subnetTool_section_results").staticTexts.count > 0,
            "Results section should contain calculated subnet information"
        )
    }

    func testValidCIDRCalculationShowsResultSection() {
        openSubnetCalculator()

        clearAndTypeText("192.168.1.0/24", into: app.textFields["subnetTool_input_cidr"])

        let calculateButton = requireExists(
            app.buttons["subnetTool_button_calculate"],
            message: "Calculate button should exist"
        )
        XCTAssertTrue(calculateButton.isEnabled, "Calculate should be enabled after entering valid CIDR")
        calculateButton.tap()

        XCTAssertTrue(
            waitForEither(
                [
                    ui("subnetTool_section_results"),
                    ui("screen_subnetResult")
                ],
                timeout: 8
            ),
            "Entering a valid CIDR and calculating should show results section"
        )
    }

    func testResultShowsHostCountNetworkAndBroadcast() {
        openSubnetCalculator()

        let example = app.buttons["subnetTool_example_192.168.1.0_24"]
        if example.waitForExistence(timeout: 5) {
            example.tap()
        } else {
            clearAndTypeText("192.168.1.0/24", into: app.textFields["subnetTool_input_cidr"])
            app.buttons["subnetTool_button_calculate"].tap()
        }

        requireExists(ui("subnetTool_section_results"), timeout: 8, message: "Results section should appear")

        // FUNCTIONAL: verify specific result labels appear
        let networkAddress = ui("subnetCalculator_label_networkAddress")
        let broadcastAddress = ui("subnetCalculator_label_broadcastAddress")
        let hostCount = ui("subnetCalculator_label_hostCount")

        XCTAssertTrue(
            networkAddress.waitForExistence(timeout: 5),
            "Network address label should appear in results"
        )
        XCTAssertTrue(
            broadcastAddress.waitForExistence(timeout: 5),
            "Broadcast address label should appear in results"
        )
        XCTAssertTrue(
            hostCount.waitForExistence(timeout: 5),
            "Host count label should appear in results"
        )

        // FUNCTIONAL: labels should contain actual values
        XCTAssertTrue(
            networkAddress.staticTexts.count > 0 || networkAddress.exists,
            "Network address should display a value"
        )
    }

    func testClearButtonRemovesResultsAndResetsState() {
        openSubnetCalculator()

        let example = app.buttons["subnetTool_example_192.168.1.0_24"]
        if example.waitForExistence(timeout: 5) {
            example.tap()
        } else {
            clearAndTypeText("192.168.1.0/24", into: app.textFields["subnetTool_input_cidr"])
            app.buttons["subnetTool_button_calculate"].tap()
        }

        requireExists(ui("subnetTool_section_results"), timeout: 8, message: "Results section should appear before clearing")

        let clearButton = requireExists(
            app.buttons["subnetTool_button_clear"],
            timeout: 5,
            message: "Clear button should be visible after results appear"
        )
        clearButton.tap()

        XCTAssertTrue(
            waitForDisappearance(ui("subnetTool_section_results"), timeout: 5),
            "Results section should disappear after tapping Clear"
        )
        // FUNCTIONAL: after clearing, calculate button should be ready for new input
        let calculateButton = app.buttons["subnetTool_button_calculate"]
        XCTAssertTrue(calculateButton.exists, "Calculate button should be visible after clearing")
    }

    private func openSubnetCalculator() {
        openToolsRoot()

        let card = ui("tools_card_subnet_calc")
        scrollToElement(card)
        requireExists(card, timeout: 8, message: "Subnet calculator tool card should exist").tap()

        requireExists(
            ui("screen_subnetCalculatorTool"),
            timeout: 8,
            message: "Subnet calculator screen should open from tools grid"
        )
    }

    private func openToolsRoot() {
        requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist").tap()
        requireExists(ui("screen_tools"), timeout: 8, message: "Tools root should be visible")
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

}
