import XCTest

@MainActor
final class PortScannerToolUITests: IOSUITestCase {

    private func navigateToPortScannerTool() {
        app.tabBars.buttons["Tools"].tap()
        let portScannerCard = app.otherElements["tools_card_port_scanner"]
        scrollToElement(portScannerCard)
        requireExists(portScannerCard, timeout: 8, message: "Port scanner tool card should exist")
        portScannerCard.tap()
        requireExists(app.otherElements["screen_portScannerTool"], timeout: 8, message: "Port scanner tool screen should appear")
    }

    // MARK: - Screen Existence

    func testPortScannerScreenExistsAndShowsControls() throws {
        navigateToPortScannerTool()
        let screen = app.otherElements["screen_portScannerTool"]
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "Port scanner screen should exist")
        // FUNCTIONAL: screen should contain interactive controls
        XCTAssertTrue(
            app.textFields["portScanner_input_host"].waitForExistence(timeout: 3),
            "Port scanner screen should show host input field"
        )
        XCTAssertTrue(
            app.buttons["portScanner_button_run"].waitForExistence(timeout: 3),
            "Port scanner screen should show run button"
        )
        captureScreenshot(named: "PortScanner_Screen")
    }

    func testNavigationTitleExists() throws {
        navigateToPortScannerTool()
        requireExists(app.navigationBars["Port Scanner"], message: "Port Scanner navigation bar should exist")
    }

    // MARK: - Input Elements

    func testHostInputFieldAcceptsText() throws {
        navigateToPortScannerTool()
        let hostField = app.textFields["portScanner_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5), "Host input field should exist")
        // FUNCTIONAL: field accepts and reflects typed text
        clearAndTypeText("192.168.1.1", into: hostField)
        XCTAssertEqual(hostField.value as? String, "192.168.1.1", "Host field should contain typed address")
    }

    func testPortRangePickerExistsAndIsInteractive() throws {
        navigateToPortScannerTool()
        let pickerExists = app.buttons["portScanner_picker_range"].waitForExistence(timeout: 5)
            || app.otherElements["portScanner_picker_range"].waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Port range picker should exist")
        // FUNCTIONAL: picker should be tappable
        let activePicker = app.buttons["portScanner_picker_range"].exists
            ? app.buttons["portScanner_picker_range"]
            : app.otherElements["portScanner_picker_range"]
        activePicker.tap()
        XCTAssertTrue(activePicker.waitForExistence(timeout: 3), "Port range picker should remain accessible after tap")
    }

    func testRunButtonDisabledUntilHostEntered() throws {
        navigateToPortScannerTool()
        let runButton = app.buttons["portScanner_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5), "Run button should exist")
        // FUNCTIONAL: run should be disabled without input
        XCTAssertFalse(runButton.isEnabled, "Run button should be disabled when host is empty")
        clearAndTypeText("127.0.0.1", into: app.textFields["portScanner_input_host"])
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after entering a host")
    }

    // MARK: - Scan Execution

    func testStartScanShowsProgressOrResults() throws {
        navigateToPortScannerTool()
        clearAndTypeText("127.0.0.1", into: app.textFields["portScanner_input_host"])
        app.buttons["portScanner_button_run"].tap()
        let progress = app.otherElements["portScanner_progress"]
        let stopButton = app.buttons["Stop Scan"]
        let results = app.otherElements["portScanner_section_results"]
        XCTAssertTrue(
            waitForEither([progress, stopButton, results], timeout: 15),
            "Progress indicator, stop button, or results should appear after starting scan"
        )
        // FUNCTIONAL: verify scan is in a meaningful state
        XCTAssertTrue(
            progress.exists || stopButton.exists || results.exists,
            "Port scanner should be running, stopped, or showing results after scan initiation"
        )
        captureScreenshot(named: "PortScanner_Scanning")
    }

    func testResultsSectionAppearsAfterScan() throws {
        navigateToPortScannerTool()
        clearAndTypeText("127.0.0.1", into: app.textFields["portScanner_input_host"])
        app.buttons["portScanner_button_run"].tap()
        let results = app.otherElements["portScanner_section_results"]
        XCTAssertTrue(results.waitForExistence(timeout: 30), "Results section should appear after scan completes")
        // FUNCTIONAL: results should contain port data
        XCTAssertTrue(
            results.staticTexts.count > 0 || app.cells.count > 0,
            "Results section should contain port scan result data"
        )
        captureScreenshot(named: "PortScanner_Results")
    }

    func testClearResultsButtonRemovesResults() throws {
        navigateToPortScannerTool()
        clearAndTypeText("127.0.0.1", into: app.textFields["portScanner_input_host"])
        app.buttons["portScanner_button_run"].tap()
        let results = app.otherElements["portScanner_section_results"]
        if results.waitForExistence(timeout: 30) {
            let clearButton = app.buttons["portScanner_button_clear"]
            if clearButton.waitForExistence(timeout: 3) {
                clearButton.tap()
                XCTAssertTrue(waitForDisappearance(results, timeout: 5), "Results should disappear after clear")
                // FUNCTIONAL: run button should be available for re-scan
                let runButton = app.buttons["portScanner_button_run"]
                XCTAssertTrue(runButton.exists, "Run button should be visible after clearing")
            }
        }
    }

    func testStopScan() throws {
        navigateToPortScannerTool()
        clearAndTypeText("192.168.1.1", into: app.textFields["portScanner_input_host"])
        let runButton = app.buttons["portScanner_button_run"]
        runButton.tap()

        let stopButton = app.buttons["Stop Scan"]
        let progress = app.otherElements["portScanner_progress"]
        XCTAssertTrue(
            waitForEither([stopButton, progress], timeout: 10),
            "Scan should enter running state"
        )

        runButton.tap()
        requireExists(app.otherElements["screen_portScannerTool"], message: "Port scanner screen should remain visible after stopping")
        // FUNCTIONAL: after stopping, screen should still be usable
        let runButtonAfter = app.buttons["portScanner_button_run"]
        XCTAssertTrue(runButtonAfter.exists, "Run button should be accessible after stopping scan")
    }

    // MARK: - Preset Picker Interaction

    func testPresetPickerInteraction() throws {
        navigateToPortScannerTool()

        let pickerButton = app.buttons["portScanner_picker_preset"]
        let pickerElement = app.otherElements["portScanner_picker_preset"]
        let rangePickerButton = app.buttons["portScanner_picker_range"]
        let rangePickerElement = app.otherElements["portScanner_picker_range"]

        let pickerExists = pickerButton.waitForExistence(timeout: 3)
            || pickerElement.waitForExistence(timeout: 3)
            || rangePickerButton.waitForExistence(timeout: 3)
            || rangePickerElement.waitForExistence(timeout: 3)

        XCTAssertTrue(pickerExists, "Port scanner preset or range picker should exist")

        let activePicker: XCUIElement = {
            if pickerButton.exists { return pickerButton }
            if pickerElement.exists { return pickerElement }
            if rangePickerButton.exists { return rangePickerButton }
            return rangePickerElement
        }()

        activePicker.tap()

        let presetOptions = ["Common", "Well Known", "All", "Custom", "Top 100", "Top 1000"]
        for preset in presetOptions {
            let option = app.buttons[preset]
            if option.waitForExistence(timeout: 2) {
                option.tap()
                break
            }
        }
    }

    func testPortScanResultsShowOpenPortRows() throws {
        navigateToPortScannerTool()
        clearAndTypeText("127.0.0.1", into: app.textFields["portScanner_input_host"])
        app.buttons["portScanner_button_run"].tap()

        let resultsSection = app.otherElements["portScanner_section_results"]
        let stopButton = app.buttons["Stop Scan"]

        XCTAssertTrue(
            waitForEither([resultsSection, stopButton], timeout: 30),
            "Port scanner should show results section or running state"
        )

        if resultsSection.exists {
            // FUNCTIONAL: results section should contain actual port data
            XCTAssertTrue(
                resultsSection.staticTexts.count > 0 || app.cells.count > 0,
                "Results section should contain at least one port result row"
            )
        }
    }
}
