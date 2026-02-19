import XCTest

final class TracerouteToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Tools"].tap()
        let tracerouteCard = app.otherElements["tools_card_traceroute"]
        if tracerouteCard.waitForExistence(timeout: 5) {
            tracerouteCard.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testTracerouteScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_tracerouteTool"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Traceroute"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Elements

    func testHostInputFieldExists() throws {
        XCTAssertTrue(app.textFields["tracerouteTool_input_host"].waitForExistence(timeout: 5))
    }

    func testMaxHopsPickerExists() throws {
        XCTAssertTrue(app.buttons["tracerouteTool_picker_maxHops"].waitForExistence(timeout: 5) ||
                      app.otherElements["tracerouteTool_picker_maxHops"].waitForExistence(timeout: 3))
    }

    func testRunButtonExists() throws {
        XCTAssertTrue(app.buttons["tracerouteTool_button_run"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Interaction

    func testTypeHostAddress() throws {
        let hostField = app.textFields["tracerouteTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("google.com")
        XCTAssertEqual(hostField.value as? String, "google.com")
    }

    // MARK: - Trace Execution

    func testStartTrace() throws {
        let hostField = app.textFields["tracerouteTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        let runButton = app.buttons["tracerouteTool_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 3))
        runButton.tap()

        // Hops section should appear
        let hopsSection = app.otherElements["tracerouteTool_section_hops"]
        XCTAssertTrue(hopsSection.waitForExistence(timeout: 15))
    }

    func testHopRowsAppear() throws {
        let hostField = app.textFields["tracerouteTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        app.buttons["tracerouteTool_button_run"].tap()

        // At least hop 1 should appear
        let firstHop = app.otherElements["tracerouteTool_hop_1"]
        XCTAssertTrue(firstHop.waitForExistence(timeout: 15))
    }

    func testClearResultsButton() throws {
        let hostField = app.textFields["tracerouteTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        app.buttons["tracerouteTool_button_run"].tap()

        let hopsSection = app.otherElements["tracerouteTool_section_hops"]
        if hopsSection.waitForExistence(timeout: 15) {
            let clearButton = app.buttons["tracerouteTool_button_clear"]
            if clearButton.waitForExistence(timeout: 30) {
                clearButton.tap()
                XCTAssertFalse(hopsSection.exists)
            }
        }
    }
}
