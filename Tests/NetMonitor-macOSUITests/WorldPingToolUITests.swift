import XCTest

@MainActor
final class WorldPingToolUITests: MacOSUITestCase {

    private func openWorldPing() {
        navigateToSidebar("tools")
        let card = ui("tools_card_world_ping").firstMatch
        requireExists(card, timeout: 5, message: "World Ping card should exist in tools grid")
        card.click()
    }

    // MARK: - Screen & Navigation

    func testWorldPingCardExistsInToolsGrid() {
        navigateToSidebar("tools")
        let card = ui("tools_card_world_ping").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "World Ping tool card should exist in tools grid")
        captureScreenshot(named: "WorldPing_CardInGrid")
    }

    // MARK: - Input Validation

    func testRunButtonExistsAndInitiallyDisabled() {
        openWorldPing()
        let runButton = requireExists(app.buttons["worldPing_button_run"], message: "Run button not found")
        XCTAssertFalse(runButton.isEnabled, "Run button should be disabled without host input")
        captureScreenshot(named: "WorldPing_Screen")
    }

    func testRunButtonEnabledAfterInput() {
        openWorldPing()
        let input = requireExists(app.textFields["worldPing_textfield_host"], message: "Host input field not found")
        clearAndTypeText("google.com", into: input)
        let runButton = app.buttons["worldPing_button_run"]
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after entering host")
    }

    // MARK: - Execution

    func testClearButtonAppearsAfterResults() throws {
        openWorldPing()
        let input = requireExists(app.textFields["worldPing_textfield_host"], message: "Host input field not found")
        clearAndTypeText("google.com", into: input)
        app.buttons["worldPing_button_run"].click()

        let results = ui("worldPing_section_results")
        if results.waitForExistence(timeout: 30) {
            XCTAssertTrue(
                app.buttons["worldPing_button_clear"].waitForExistence(timeout: 5),
                "Clear button should appear after results"
            )
            captureScreenshot(named: "WorldPing_Results")
        } else {
            throw XCTSkip("Network unavailable; skipping results check")
        }
    }
}
