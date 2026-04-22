import XCTest

@MainActor
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

        // Verify real hop rows appear — every `TracerouteHop` renders with
        // identifier `traceroute_row_<hopNumber>`. Hop #1 (first upstream gateway)
        // should arrive first.
        let firstHop = ui("traceroute_row_1")
        XCTAssertTrue(
            firstHop.waitForExistence(timeout: 20),
            "Traceroute should render hop #1 when tracing 1.1.1.1"
        )
        captureScreenshot(named: "Traceroute_Running")
    }

    func testTracerouteShowsResults() {
        openTraceroute()
        clearAndTypeText("8.8.8.8", into: app.textFields["traceroute_textfield_host"])
        app.buttons["traceroute_button_run"].tap()

        // After the trace completes, the Clear button appears only when
        // `!hops.isEmpty && !isRunning` — proving hops were recorded.
        let clearButton = app.buttons["traceroute_button_clear"]
        XCTAssertTrue(
            clearButton.waitForExistence(timeout: 60),
            "Clear button should appear after traceroute produces hop data"
        )

        let anyHop = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'traceroute_row_'"))
        XCTAssertGreaterThan(
            anyHop.count, 0,
            "Traceroute should render at least one traceroute_row_* hop result"
        )
        captureScreenshot(named: "Traceroute_Results")
    }
}
