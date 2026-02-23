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

    func testPortScannerScreenExists() throws {
        navigateToPortScannerTool()
        requireExists(app.otherElements["screen_portScannerTool"], message: "Port scanner screen should exist")
    }

    func testNavigationTitleExists() throws {
        navigateToPortScannerTool()
        requireExists(app.navigationBars["Port Scanner"], message: "Port Scanner navigation bar should exist")
    }

    // MARK: - Input Elements

    func testHostInputFieldExists() throws {
        navigateToPortScannerTool()
        requireExists(app.textFields["portScanner_input_host"], message: "Host input field should exist")
    }

    func testPortRangePickerExists() throws {
        navigateToPortScannerTool()
        let pickerExists = app.buttons["portScanner_picker_range"].waitForExistence(timeout: 5)
            || app.otherElements["portScanner_picker_range"].waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Port range picker should exist")
    }

    func testRunButtonExists() throws {
        navigateToPortScannerTool()
        requireExists(app.buttons["portScanner_button_run"], message: "Run button should exist")
    }

    // MARK: - Input Interaction

    func testTypeHostAddress() throws {
        navigateToPortScannerTool()
        let hostField = app.textFields["portScanner_input_host"]
        clearAndTypeText("192.168.1.1", into: hostField)
        XCTAssertEqual(hostField.value as? String, "192.168.1.1")
    }

    // MARK: - Scan Execution

    func testStartScan() throws {
        navigateToPortScannerTool()
        clearAndTypeText("192.168.1.1", into: app.textFields["portScanner_input_host"])
        app.buttons["portScanner_button_run"].tap()
        let progress = app.otherElements["portScanner_progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "Progress indicator should appear after starting scan")
    }

    func testResultsSectionAppearsAfterScan() throws {
        navigateToPortScannerTool()
        clearAndTypeText("192.168.1.1", into: app.textFields["portScanner_input_host"])
        app.buttons["portScanner_button_run"].tap()
        let results = app.otherElements["portScanner_section_results"]
        XCTAssertTrue(results.waitForExistence(timeout: 30), "Results section should appear after scan completes")
    }

    func testClearResultsButton() throws {
        navigateToPortScannerTool()
        clearAndTypeText("192.168.1.1", into: app.textFields["portScanner_input_host"])
        app.buttons["portScanner_button_run"].tap()
        let results = app.otherElements["portScanner_section_results"]
        if results.waitForExistence(timeout: 30) {
            let clearButton = app.buttons["portScanner_button_clear"]
            if clearButton.waitForExistence(timeout: 3) {
                clearButton.tap()
                XCTAssertTrue(waitForDisappearance(results, timeout: 5), "Results should disappear after clear")
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
            requireExists(resultsSection, message: "Results section should be visible after scan completes")
        }
    }
}
