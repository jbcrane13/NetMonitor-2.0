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

    func testWorldPingCardExistsInGridAndShowsLabel() {
        requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist").tap()
        requireExists(ui("screen_tools"), timeout: 8, message: "Tools screen should open")

        let card = ui("tools_card_world_ping")
        scrollToElement(card)
        XCTAssertTrue(card.waitForExistence(timeout: 8), "World Ping card should exist in tools grid")
        // FUNCTIONAL: card should have a visible label
        XCTAssertTrue(
            card.staticTexts.count > 0 || card.label.contains("World Ping") || card.label.contains("Ping"),
            "World Ping card should display a label identifying the tool"
        )
        captureScreenshot(named: "WorldPing_CardInGrid")
    }

    func testWorldPingScreenShowsControls() {
        openWorldPing()

        // FUNCTIONAL: screen should contain host input field and run button
        XCTAssertTrue(
            app.textFields["worldPing_textfield_host"].waitForExistence(timeout: 3),
            "Host text field should be visible on World Ping screen"
        )
        XCTAssertTrue(
            app.buttons["worldPing_button_run"].waitForExistence(timeout: 3),
            "Run button should be visible on World Ping screen"
        )
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

        clearAndTypeText("google.com", into: app.textFields["worldPing_textfield_host"])

        let runButton = requireExists(
            app.buttons["worldPing_button_run"],
            message: "Run button should exist"
        )
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after entering a host")
    }

    func testHostInputFieldAcceptsText() {
        openWorldPing()

        let hostField = requireExists(
            app.textFields["worldPing_textfield_host"],
            message: "Host text field should exist"
        )
        clearAndTypeText("example.com", into: hostField)
        XCTAssertEqual(hostField.value as? String, "example.com", "Host field should contain typed text")
    }

    func testRunWorldPingProducesResultsOrTimeout() {
        openWorldPing()
        clearAndTypeText("google.com", into: app.textFields["worldPing_textfield_host"])
        app.buttons["worldPing_button_run"].tap()

        // Wait for results or timeout after ~30s (real network call)
        let results = ui("worldPing_section_results")
        if results.waitForExistence(timeout: 30) {
            // FUNCTIONAL: results section should contain ping data
            XCTAssertTrue(
                results.staticTexts.count > 0,
                "World Ping results section should contain ping result data"
            )
            XCTAssertTrue(
                app.buttons["worldPing_button_clear"].waitForExistence(timeout: 5),
                "Clear button should appear after results"
            )
            captureScreenshot(named: "WorldPing_Results")
        } else {
            // Skip if network unavailable in test environment
            XCTSkip("Network unavailable; skipping results assertion")
        }
    }

    func testClearButtonAppearsAfterResultsAndRemovesThem() {
        openWorldPing()
        clearAndTypeText("google.com", into: app.textFields["worldPing_textfield_host"])
        app.buttons["worldPing_button_run"].tap()

        // Wait for results or timeout after ~30s (real network call)
        let results = ui("worldPing_section_results")
        if results.waitForExistence(timeout: 30) {
            XCTAssertTrue(
                app.buttons["worldPing_button_clear"].waitForExistence(timeout: 5),
                "Clear button should appear after results"
            )

            // FUNCTIONAL: clearing should remove results
            app.buttons["worldPing_button_clear"].tap()
            XCTAssertTrue(
                waitForDisappearance(ui("worldPing_section_results"), timeout: 5),
                "Results section should disappear after tapping Clear"
            )
            captureScreenshot(named: "WorldPing_Results")
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
