@preconcurrency import XCTest

final class TracerouteToolUITests: IOSUITestCase {

    private func navigateToTracerouteTool() {
        app.tabBars.buttons["Tools"].tap()
        let tracerouteCard = app.otherElements["tools_card_traceroute"]
        scrollToElement(tracerouteCard)
        requireExists(tracerouteCard, timeout: 8, message: "Traceroute tool card should exist")
        tracerouteCard.tap()
        requireExists(app.otherElements["screen_tracerouteTool"], timeout: 8, message: "Traceroute tool screen should appear")
    }

    // MARK: - Screen Existence

    func testTracerouteScreenExists() throws {
        navigateToTracerouteTool()
        requireExists(app.otherElements["screen_tracerouteTool"], message: "Traceroute screen should exist")
        captureScreenshot(named: "Traceroute_Screen")
    }

    func testNavigationTitleExists() throws {
        navigateToTracerouteTool()
        requireExists(app.navigationBars["Traceroute"], message: "Traceroute navigation bar should exist")
    }

    // MARK: - Input Elements

    func testHostInputFieldExists() throws {
        navigateToTracerouteTool()
        requireExists(app.textFields["tracerouteTool_input_host"], message: "Host input field should exist")
    }

    func testMaxHopsPickerExists() throws {
        navigateToTracerouteTool()
        let pickerExists = app.buttons["tracerouteTool_picker_maxHops"].waitForExistence(timeout: 5)
            || app.otherElements["tracerouteTool_picker_maxHops"].waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Max hops picker should exist")
    }

    func testRunButtonExists() throws {
        navigateToTracerouteTool()
        requireExists(app.buttons["tracerouteTool_button_run"], message: "Run button should exist")
    }

    // MARK: - Input Interaction

    func testTypeHostAddress() throws {
        navigateToTracerouteTool()
        let hostField = app.textFields["tracerouteTool_input_host"]
        clearAndTypeText("google.com", into: hostField)
        XCTAssertEqual(hostField.value as? String, "google.com")
    }

    // MARK: - Trace Execution

    func testStartTrace() throws {
        navigateToTracerouteTool()
        clearAndTypeText("8.8.8.8", into: app.textFields["tracerouteTool_input_host"])
        app.buttons["tracerouteTool_button_run"].tap()
        let hopsSection = app.otherElements["tracerouteTool_section_hops"]
        XCTAssertTrue(hopsSection.waitForExistence(timeout: 15), "Hops section should appear after starting trace")
        captureScreenshot(named: "Traceroute_HopsAppearing")
    }

    func testHopRowsAppear() throws {
        navigateToTracerouteTool()
        clearAndTypeText("8.8.8.8", into: app.textFields["tracerouteTool_input_host"])
        app.buttons["tracerouteTool_button_run"].tap()
        let firstHop = app.otherElements["tracerouteTool_row_1"]
        XCTAssertTrue(firstHop.waitForExistence(timeout: 15), "First hop row should appear")
    }

    func testClearResultsButton() throws {
        navigateToTracerouteTool()
        clearAndTypeText("8.8.8.8", into: app.textFields["tracerouteTool_input_host"])
        app.buttons["tracerouteTool_button_run"].tap()
        let hopsSection = app.otherElements["tracerouteTool_section_hops"]
        if hopsSection.waitForExistence(timeout: 15) {
            let clearButton = app.buttons["tracerouteTool_button_clear"]
            if clearButton.waitForExistence(timeout: 30) {
                clearButton.tap()
                XCTAssertTrue(waitForDisappearance(hopsSection, timeout: 5), "Hops section should disappear after clear")
            }
        }
    }

    // MARK: - Max Hops Picker

    func testMaxHopsPickerExistsOnScreen() throws {
        navigateToTracerouteTool()
        let pickerButton = app.buttons["tracerouteTool_picker_maxHops"]
        let pickerElement = app.otherElements["tracerouteTool_picker_maxHops"]
        let pickerExists = pickerButton.waitForExistence(timeout: 5) || pickerElement.waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Max hops picker should be visible on the traceroute tool screen")
    }

    // MARK: - Hops Section After Run

    func testTracerouteHopsSectionAppearsAfterRun() throws {
        navigateToTracerouteTool()
        clearAndTypeText("1.1.1.1", into: app.textFields["tracerouteTool_input_host"])
        app.buttons["tracerouteTool_button_run"].tap()

        let hopsSection = app.otherElements["tracerouteTool_section_hops"]
        let stopButton = app.buttons["Stop Trace"]

        XCTAssertTrue(
            waitForEither([hopsSection, stopButton], timeout: 20),
            "Traceroute should show hops section or running state after starting"
        )

        if hopsSection.exists {
            let firstHop = app.otherElements["tracerouteTool_row_1"]
            XCTAssertTrue(
                firstHop.waitForExistence(timeout: 10),
                "At least one hop row should appear in the hops section"
            )
            captureScreenshot(named: "Traceroute_HopRows")
        }
    }
}
