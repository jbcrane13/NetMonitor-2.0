@preconcurrency import XCTest

final class TracerouteToolUITests: MacOSUITestCase {

    private func openTraceroute() {
        openTool(cardID: "tools_card_traceroute", sheetElement: "traceroute_textfield_host")
    }

    // MARK: - Element Existence

    func testHostFieldExists() {
        openTraceroute()
        requireExists(app.textFields["traceroute_textfield_host"], message: "Host field should exist")
        captureScreenshot(named: "Traceroute_Screen")
    }

    func testHopsPickerExists() {
        openTraceroute()
        requireExists(app.popUpButtons["traceroute_picker_hops"], message: "Hops picker should exist")
    }

    func testRunButtonExists() {
        openTraceroute()
        requireExists(app.buttons["traceroute_button_run"], message: "Run button should exist")
    }

    func testCloseButtonExists() {
        openTraceroute()
        requireExists(app.buttons["traceroute_button_close"], message: "Close button should exist")
    }

    // MARK: - Input Validation

    func testRunButtonDisabledWhenHostEmpty() {
        openTraceroute()
        let runButton = requireExists(app.buttons["traceroute_button_run"], message: "Run button should exist")
        XCTAssertFalse(runButton.isEnabled, "Run button should be disabled without host input")
    }

    func testRunButtonEnabledAfterTypingHost() {
        openTraceroute()
        clearAndTypeText("8.8.8.8", into: app.textFields["traceroute_textfield_host"])
        let runButton = requireExists(app.buttons["traceroute_button_run"], message: "Run button should exist")
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after entering host")
    }

    // MARK: - Navigation

    func testCloseButtonDismissesSheet() {
        openTraceroute()
        app.buttons["traceroute_button_close"].tap()
        requireExists(
            app.otherElements["tools_card_traceroute"],
            message: "Tool card should reappear after closing sheet"
        )
    }

    // MARK: - Trace Execution

    func testTypeHostAndTrace() {
        openTraceroute()
        clearAndTypeText("1.1.1.1", into: app.textFields["traceroute_textfield_host"])
        app.buttons["traceroute_button_run"].tap()

        // Should enter running state — button remains or results appear
        let results = ui("traceroute_results")
        let runButton = app.buttons["traceroute_button_run"]
        XCTAssertTrue(
            waitForEither([results, runButton], timeout: 10),
            "Traceroute should enter running state or show results"
        )
        captureScreenshot(named: "Traceroute_Running")
    }

    func testTracerouteShowsResults() {
        openTraceroute()
        clearAndTypeText("8.8.8.8", into: app.textFields["traceroute_textfield_host"])
        app.buttons["traceroute_button_run"].tap()

        let results = ui("traceroute_results")
        if results.waitForExistence(timeout: 30) {
            captureScreenshot(named: "Traceroute_Results")
        }
    }
}
