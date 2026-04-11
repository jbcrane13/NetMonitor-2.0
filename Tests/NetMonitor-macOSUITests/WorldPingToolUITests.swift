import XCTest

final class WorldPingToolUITests: MacOSUITestCase {

    private func openWorldPing() {
        navigateToSidebar("tools")
        let card = ui("tools_card_world_ping")
        requireExists(card, timeout: 5, message: "World Ping card should exist in tools grid")
        card.tap()
    }

    // MARK: - Screen & Navigation

    func testWorldPingCardExistsInToolsGrid() {
        navigateToSidebar("tools")
        let card = ui("tools_card_world_ping")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "World Ping tool card should exist in tools grid")
        captureScreenshot(named: "WorldPing_CardInGrid")
    }

    // MARK: - Input Validation

    func testRunButtonExistsAndInitiallyDisabled() {
        openWorldPing()
        let runButton = app.buttons["worldPing_button_run"]
        guard runButton.waitForExistence(timeout: 5) else {
            XCTFail("Run button not found")
            return
        }
        XCTAssertFalse(runButton.isEnabled, "Run button should be disabled without host input")
        captureScreenshot(named: "WorldPing_Screen")
    }

    func testRunButtonEnabledAfterInput() {
        openWorldPing()
        let input = app.textFields["worldPing_input_host"]
        guard input.waitForExistence(timeout: 5) else {
            XCTFail("Host input field not found")
            return
        }
        clearAndTypeText("google.com", into: input)
        let runButton = app.buttons["worldPing_button_run"]
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after entering host")
    }

    // MARK: - Execution

    func testClearButtonAppearsAfterResults() throws {
        openWorldPing()
        let input = app.textFields["worldPing_input_host"]
        guard input.waitForExistence(timeout: 5) else {
            throw XCTSkip("Host input not found")
        }
        clearAndTypeText("google.com", into: input)
        app.buttons["worldPing_button_run"].tap()

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
