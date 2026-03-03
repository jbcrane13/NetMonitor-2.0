import XCTest

@MainActor
final class TracerouteToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools
        let sidebar = app.descendants(matching: .any)["sidebar_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        // Open Traceroute tool
        let card = app.otherElements["tools_card_traceroute"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Element Existence

    func testHostFieldExists() {
        XCTAssertTrue(app.textFields["traceroute_textfield_host"].waitForExistence(timeout: 3))
    }

    func testHopsPickerExists() {
        XCTAssertTrue(app.popUpButtons["traceroute_picker_hops"].waitForExistence(timeout: 3))
    }

    func testRunButtonExists() {
        XCTAssertTrue(app.buttons["traceroute_button_run"].waitForExistence(timeout: 3))
    }

    func testCloseButtonExists() {
        XCTAssertTrue(app.buttons["traceroute_button_close"].waitForExistence(timeout: 3))
    }

    // MARK: - Interactions

    func testRunButtonDisabledWhenHostEmpty() {
        let runButton = app.buttons["traceroute_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 3))
        XCTAssertFalse(runButton.isEnabled)
    }

    func testRunButtonEnabledAfterTypingHost() {
        let hostField = app.textFields["traceroute_textfield_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 3))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        XCTAssertTrue(app.buttons["traceroute_button_run"].isEnabled)
    }

    func testCloseButtonDismissesSheet() {
        app.buttons["traceroute_button_close"].tap()
        XCTAssertTrue(app.otherElements["tools_card_traceroute"].waitForExistence(timeout: 3))
    }

    func testTypeHostAndTrace() {
        let hostField = app.textFields["traceroute_textfield_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 3))
        hostField.tap()
        hostField.typeText("1.1.1.1")

        app.buttons["traceroute_button_run"].tap()

        // Button should remain visible (changes to "Stop")
        XCTAssertTrue(app.buttons["traceroute_button_run"].waitForExistence(timeout: 3))
    }
}
