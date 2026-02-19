import XCTest

final class PortScannerToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Tools"].tap()
        let portScannerCard = app.otherElements["tools_card_port_scanner"]
        if portScannerCard.waitForExistence(timeout: 5) {
            portScannerCard.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testPortScannerScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_portScannerTool"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Port Scanner"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Elements

    func testHostInputFieldExists() throws {
        XCTAssertTrue(app.textFields["portScanner_input_host"].waitForExistence(timeout: 5))
    }

    func testPortRangePickerExists() throws {
        XCTAssertTrue(app.buttons["portScanner_picker_range"].waitForExistence(timeout: 5) ||
                      app.otherElements["portScanner_picker_range"].waitForExistence(timeout: 3))
    }

    func testRunButtonExists() throws {
        XCTAssertTrue(app.buttons["portScanner_button_run"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Interaction

    func testTypeHostAddress() throws {
        let hostField = app.textFields["portScanner_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("192.168.1.1")
        XCTAssertEqual(hostField.value as? String, "192.168.1.1")
    }

    // MARK: - Scan Execution

    func testStartScan() throws {
        let hostField = app.textFields["portScanner_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("192.168.1.1")

        let runButton = app.buttons["portScanner_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 3))
        runButton.tap()

        // Progress section should appear
        let progress = app.otherElements["portScanner_progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
    }

    func testResultsSectionAppearsAfterScan() throws {
        let hostField = app.textFields["portScanner_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("192.168.1.1")

        app.buttons["portScanner_button_run"].tap()

        // Results section should appear after scan completes
        let results = app.otherElements["portScanner_section_results"]
        XCTAssertTrue(results.waitForExistence(timeout: 30))
    }

    func testClearResultsButton() throws {
        let hostField = app.textFields["portScanner_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("192.168.1.1")

        app.buttons["portScanner_button_run"].tap()

        let results = app.otherElements["portScanner_section_results"]
        if results.waitForExistence(timeout: 30) {
            let clearButton = app.buttons["portScanner_button_clear"]
            if clearButton.waitForExistence(timeout: 3) {
                clearButton.tap()
                XCTAssertFalse(results.exists)
            }
        }
    }

    func testStopScan() throws {
        let hostField = app.textFields["portScanner_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("192.168.1.1")

        let runButton = app.buttons["portScanner_button_run"]
        runButton.tap()

        // Wait briefly then stop
        sleep(2)
        runButton.tap()

        // Screen should still be visible
        XCTAssertTrue(app.otherElements["screen_portScannerTool"].exists)
    }
}
