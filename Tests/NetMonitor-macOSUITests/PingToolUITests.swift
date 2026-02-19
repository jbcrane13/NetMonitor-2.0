import XCTest

@MainActor
final class PingToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools
        let sidebar = app.staticTexts["sidebar_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        // Open Ping tool
        let pingCard = app.otherElements["tools_card_ping"]
        XCTAssertTrue(pingCard.waitForExistence(timeout: 3))
        pingCard.tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Element Existence

    func testHostFieldExists() {
        XCTAssertTrue(app.textFields["ping_textfield_host"].waitForExistence(timeout: 3))
    }

    func testCountPickerExists() {
        XCTAssertTrue(app.popUpButtons["ping_picker_count"].waitForExistence(timeout: 3))
    }

    func testRunButtonExists() {
        XCTAssertTrue(app.buttons["ping_button_run"].waitForExistence(timeout: 3))
    }

    func testCloseButtonExists() {
        XCTAssertTrue(app.buttons["ping_button_close"].waitForExistence(timeout: 3))
    }

    // MARK: - Interactions

    func testRunButtonDisabledWhenHostEmpty() {
        let runButton = app.buttons["ping_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 3))
        XCTAssertFalse(runButton.isEnabled)
    }

    func testRunButtonEnabledAfterTypingHost() {
        let hostField = app.textFields["ping_textfield_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 3))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        let runButton = app.buttons["ping_button_run"]
        XCTAssertTrue(runButton.isEnabled)
    }

    func testCloseButtonDismissesSheet() {
        let closeButton = app.buttons["ping_button_close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.tap()

        // Sheet should dismiss, tool cards should be visible again
        XCTAssertTrue(app.otherElements["tools_card_ping"].waitForExistence(timeout: 3))
    }

    func testTypeHostAndRun() {
        let hostField = app.textFields["ping_textfield_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 3))
        hostField.tap()
        hostField.typeText("127.0.0.1")

        app.buttons["ping_button_run"].tap()

        // Button label should change to "Stop" while running
        let stopButton = app.buttons["ping_button_run"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 3))
    }
}
