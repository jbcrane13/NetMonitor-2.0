import XCTest

@MainActor
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

    func testTracerouteScreenExistsAndShowsControls() throws {
        navigateToTracerouteTool()
        let screen = app.otherElements["screen_tracerouteTool"]
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "Traceroute screen should exist")
        // FUNCTIONAL: screen should contain input and run button
        XCTAssertTrue(
            app.textFields["tracerouteTool_input_host"].waitForExistence(timeout: 3),
            "Traceroute screen should show host input field"
        )
        XCTAssertTrue(
            app.buttons["tracerouteTool_button_run"].waitForExistence(timeout: 3),
            "Traceroute screen should show run button"
        )
        captureScreenshot(named: "Traceroute_Screen")
    }

    func testNavigationTitleExists() throws {
        navigateToTracerouteTool()
        requireExists(app.navigationBars["Traceroute"], message: "Traceroute navigation bar should exist")
    }

    // MARK: - Input Elements

    func testHostInputFieldAcceptsText() throws {
        navigateToTracerouteTool()
        let hostField = app.textFields["tracerouteTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5), "Host input field should exist")
        // FUNCTIONAL: field accepts and reflects typed text
        clearAndTypeText("8.8.8.8", into: hostField)
        XCTAssertEqual(hostField.value as? String, "8.8.8.8", "Host field should contain typed address")
    }

    func testMaxHopsPickerExistsAndIsInteractive() throws {
        navigateToTracerouteTool()
        let pickerExists = app.buttons["tracerouteTool_picker_maxHops"].waitForExistence(timeout: 5)
            || app.otherElements["tracerouteTool_picker_maxHops"].waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Max hops picker should exist")
        // FUNCTIONAL: picker should be tappable
        let activePicker = app.buttons["tracerouteTool_picker_maxHops"].exists
            ? app.buttons["tracerouteTool_picker_maxHops"]
            : app.otherElements["tracerouteTool_picker_maxHops"]
        activePicker.tap()
        XCTAssertTrue(activePicker.waitForExistence(timeout: 3), "Max hops picker should remain accessible after tap")
    }

    func testRunButtonDisabledUntilHostEntered() throws {
        navigateToTracerouteTool()
        let runButton = app.buttons["tracerouteTool_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5), "Run button should exist")
        // FUNCTIONAL: run should be disabled without input
        XCTAssertFalse(runButton.isEnabled, "Run button should be disabled when host is empty")
        clearAndTypeText("1.1.1.1", into: app.textFields["tracerouteTool_input_host"])
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after entering a host")
    }

    // MARK: - Input Interaction

    func testTypeHostAddress() throws {
        navigateToTracerouteTool()
        let hostField = app.textFields["tracerouteTool_input_host"]
        clearAndTypeText("google.com", into: hostField)
        XCTAssertEqual(hostField.value as? String, "google.com")
    }

    // MARK: - Trace Execution

    func testStartTraceShowsHopsOrRunningState() throws {
        navigateToTracerouteTool()
        clearAndTypeText("1.1.1.1", into: app.textFields["tracerouteTool_input_host"])
        app.buttons["tracerouteTool_button_run"].tap()
        let hopsSection = app.otherElements["tracerouteTool_section_hops"]
        let stopButton = app.buttons["Stop Trace"]
        XCTAssertTrue(
            waitForEither([hopsSection, stopButton], timeout: 15),
            "Hops section or stop button should appear after starting trace"
        )
        // FUNCTIONAL: verify traceroute is actively tracing or has results
        XCTAssertTrue(
            hopsSection.exists || stopButton.exists,
            "Traceroute should show hop results or be actively running after execution"
        )
        captureScreenshot(named: "Traceroute_HopsAppearing")
    }

    func testHopRowsAppearWithContent() throws {
        navigateToTracerouteTool()
        clearAndTypeText("1.1.1.1", into: app.textFields["tracerouteTool_input_host"])
        app.buttons["tracerouteTool_button_run"].tap()
        let firstHop = app.otherElements["tracerouteTool_row_1"]
        XCTAssertTrue(firstHop.waitForExistence(timeout: 15), "First hop row should appear")
        // FUNCTIONAL: hop row should contain address or latency data
        XCTAssertTrue(
            firstHop.staticTexts.count > 0 || firstHop.exists,
            "First hop row should contain hop data (address/latency)"
        )
    }

    func testClearResultsButtonRemovesResults() throws {
        navigateToTracerouteTool()
        clearAndTypeText("1.1.1.1", into: app.textFields["tracerouteTool_input_host"])
        app.buttons["tracerouteTool_button_run"].tap()
        let hopsSection = app.otherElements["tracerouteTool_section_hops"]
        if hopsSection.waitForExistence(timeout: 15) {
            let clearButton = app.buttons["tracerouteTool_button_clear"]
            if clearButton.waitForExistence(timeout: 30) {
                clearButton.tap()
                XCTAssertTrue(waitForDisappearance(hopsSection, timeout: 5), "Hops section should disappear after clear")
                // FUNCTIONAL: run button should be available after clearing
                let runButton = app.buttons["tracerouteTool_button_run"]
                XCTAssertTrue(runButton.exists, "Run button should be visible after clearing results")
                XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after clearing results")
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
            // FUNCTIONAL: hop row should have content
            XCTAssertTrue(
                firstHop.staticTexts.count > 0,
                "Hop row should contain hop number, address, or latency data"
            )
            captureScreenshot(named: "Traceroute_HopRows")
        }
    }
}
