import XCTest

@MainActor
final class WorldPingToolUITests: IOSUITestCase {

    private func openWorldPing() {
        requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist").tap()
        requireExists(ui("screen_tools"), timeout: 8, message: "Tools screen should open")

        let card = ui("tools_card_world_ping")
        scrollToElement(card)
        requireExists(card, timeout: 8, message: "World Ping card should exist").tap()

        requireExists(
            ui("screen_worldPingTool"),
            timeout: 8,
            message: "World Ping screen should open"
        )
    }

    func testWorldPingCardExistsInGrid() {
        requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist").tap()
        requireExists(ui("screen_tools"), timeout: 8, message: "Tools screen should open")

        let card = ui("tools_card_world_ping")
        scrollToElement(card)
        XCTAssertTrue(card.waitForExistence(timeout: 8), "World Ping card should exist in tools grid")
    }

    func testRunButtonExistsAndIsDisabledWithoutInput() {
        openWorldPing()

        let runButton = requireExists(
            app.buttons["worldPing_button_run"],
            message: "Run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Run button should be disabled without host input")
    }

    func testRunButtonEnabledAfterInput() {
        openWorldPing()

        clearAndTypeText("google.com", into: app.textFields["worldPing_input_host"])

        let runButton = requireExists(
            app.buttons["worldPing_button_run"],
            message: "Run button should exist"
        )
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after entering a host")
    }

    func testClearButtonAppearsAfterResults() {
        openWorldPing()
        clearAndTypeText("google.com", into: app.textFields["worldPing_input_host"])
        app.buttons["worldPing_button_run"].tap()

        // Wait for results or timeout after ~30s (real network call)
        let results = ui("worldPing_section_results")
        if results.waitForExistence(timeout: 30) {
            XCTAssertTrue(
                app.buttons["worldPing_button_clear"].waitForExistence(timeout: 5),
                "Clear button should appear after results"
            )
        } else {
            // Skip if network unavailable in test environment
            XCTSkip("Network unavailable; skipping results assertion")
        }
    }

    // MARK: - Helpers

    private func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }
}
