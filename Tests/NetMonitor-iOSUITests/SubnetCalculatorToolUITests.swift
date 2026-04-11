import XCTest

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
        requireExists(ui("subnetTool_card_error"), timeout: 5, message: "Invalid CIDR should show error card")

        requireExists(app.buttons["subnetTool_button_clear"], message: "Clear button should be visible after result/error").tap()
        XCTAssertTrue(
            waitForDisappearance(ui("subnetTool_card_error"), timeout: 5),
            "Error card should disappear after clear"
        )
    }

    func testSubnetCalculatorExampleProducesResults() {
        openSubnetCalculator()

        let example = requireExists(
            app.buttons["subnetTool_example_192.168.1.0_24"],
            message: "Known CIDR example should be visible"
        )
        example.tap()

        requireExists(
            ui("subnetTool_section_results"),
            timeout: 8,
            message: "Selecting a valid example should produce results"
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

        requireExists(
            ui("subnetCalculator_label_networkAddress"),
            timeout: 5,
            message: "Network address label should appear in results"
        )
        requireExists(
            ui("subnetCalculator_label_broadcastAddress"),
            timeout: 5,
            message: "Broadcast address label should appear in results"
        )
        requireExists(
            ui("subnetCalculator_label_hostCount"),
            timeout: 5,
            message: "Host count label should appear in results"
        )
    }

    func testClearButtonRemovesResults() {
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
