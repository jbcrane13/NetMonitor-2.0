import XCTest

@MainActor
final class TracerouteToolUITests: MacOSUITestCase {

    private func openTraceroute() {
        openTool(cardID: "tools_card_traceroute", sheetElement: "traceroute_textfield_host")
    }

    /// The texts of the rendered hop rows.
    private var hopTexts: XCUIElementQuery {
        app.staticTexts.matching(identifier: "traceroute_section_hops")
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
        // The field is prefilled with the last-used target, so empty it first.
        clearText(in: app.textFields["traceroute_textfield_host"])
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
        closeTool(closeButtonID: "traceroute_button_close", cardID: "tools_card_traceroute")
    }

    // MARK: - Trace Execution

    func testTypeHostAndTrace() {
        openTraceroute()
        clearAndTypeText("1.1.1.1", into: app.textFields["traceroute_textfield_host"])
        app.buttons["traceroute_button_run"].click()

        // Verify real hop rows appear. On macOS 27 the list's `traceroute_section_hops` id is
        // stamped over each row's `traceroute_row_<hopNumber>`, so find hop #1 (the first
        // upstream gateway) by its hop number.
        let firstHop = hopTexts.matching(NSPredicate(format: "value MATCHES %@", "\\s*1\\s*")).firstMatch
        XCTAssertTrue(
            firstHop.waitForExistence(timeout: 20),
            "Traceroute should render hop #1 when tracing 1.1.1.1"
        )
        captureScreenshot(named: "Traceroute_Running")
    }

    func testTracerouteShowsResults() {
        openTraceroute()
        clearAndTypeText("8.8.8.8", into: app.textFields["traceroute_textfield_host"])
        app.buttons["traceroute_button_run"].click()

        // After the trace completes, the Clear button appears only when
        // `!hops.isEmpty && !isRunning` — proving hops were recorded.
        let clearButton = app.buttons["traceroute_button_clear"]
        XCTAssertTrue(
            clearButton.waitForExistence(timeout: 60),
            "Clear button should appear after traceroute produces hop data"
        )

        XCTAssertGreaterThan(
            hopTexts.count, 0,
            "Traceroute should render at least one hop result"
        )
        captureScreenshot(named: "Traceroute_Results")
    }
}
