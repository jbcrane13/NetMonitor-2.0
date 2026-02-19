import XCTest

final class PingToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools tab, then Ping
        app.tabBars.buttons["Tools"].tap()
        let pingCard = app.otherElements["tools_card_ping"]
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testPingToolScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_pingTool"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Ping"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Elements

    func testHostInputFieldExists() throws {
        XCTAssertTrue(app.textFields["pingTool_input_host"].waitForExistence(timeout: 5))
    }

    func testPingCountPickerExists() throws {
        XCTAssertTrue(app.buttons["pingTool_picker_count"].waitForExistence(timeout: 5) ||
                      app.otherElements["pingTool_picker_count"].waitForExistence(timeout: 3))
    }

    func testRunButtonExists() throws {
        XCTAssertTrue(app.buttons["pingTool_button_run"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Interaction

    func testTypeHostAddress() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")
        XCTAssertEqual(hostField.value as? String, "8.8.8.8")
    }

    func testClearHostField() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("google.com")
        // Tap the clear button on the input field
        let clearButton = app.buttons["pingTool_input_host_button_clear"]
        if clearButton.waitForExistence(timeout: 3) {
            clearButton.tap()
            XCTAssertEqual(hostField.value as? String, "" , "Field should be cleared")
        }
    }

    // MARK: - Ping Execution

    func testStartPing() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        let runButton = app.buttons["pingTool_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 3))
        runButton.tap()

        // Results section should appear
        let resultsSection = app.otherElements["pingTool_section_results"]
        XCTAssertTrue(resultsSection.waitForExistence(timeout: 10))
    }

    func testPingStatisticsAppearAfterCompletion() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        app.buttons["pingTool_button_run"].tap()

        // Wait for statistics to appear
        let statsCard = app.otherElements["pingTool_card_statistics"]
        XCTAssertTrue(statsCard.waitForExistence(timeout: 30))
    }

    func testClearResultsButton() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        app.buttons["pingTool_button_run"].tap()

        // Wait for results then clear
        let resultsSection = app.otherElements["pingTool_section_results"]
        if resultsSection.waitForExistence(timeout: 15) {
            // Wait for ping to finish
            let clearButton = app.buttons["pingTool_button_clear"]
            if clearButton.waitForExistence(timeout: 30) {
                clearButton.tap()
                XCTAssertFalse(resultsSection.exists)
            }
        }
    }
}
