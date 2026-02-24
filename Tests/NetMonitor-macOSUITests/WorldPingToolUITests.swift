import XCTest

@MainActor
final class WorldPingToolUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Helpers

    private func openWorldPing() {
        let card = app.buttons["tools_card_world_ping"]
        if card.waitForExistence(timeout: 5) {
            card.click()
        }
    }

    // MARK: - Tests

    func testWorldPingCardExistsInToolsGrid() {
        let card = app.buttons["tools_card_world_ping"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "World Ping tool card should exist in tools grid")
    }

    func testRunButtonExistsAndInitiallyDisabled() {
        openWorldPing()

        let runButton = app.buttons["worldPing_button_run"]
        guard runButton.waitForExistence(timeout: 5) else {
            XCTFail("Run button not found")
            return
        }
        XCTAssertFalse(runButton.isEnabled, "Run button should be disabled without host input")
    }

    func testInputFieldAcceptsText() {
        openWorldPing()

        let input = app.textFields["worldPing_input_host"]
        guard input.waitForExistence(timeout: 5) else {
            XCTFail("Host input field not found")
            return
        }

        input.click()
        input.typeText("google.com")

        XCTAssertTrue(
            app.buttons["worldPing_button_run"].isEnabled,
            "Run button should be enabled after entering host"
        )
    }

    func testClearButtonAppearsAfterResults() {
        openWorldPing()

        let input = app.textFields["worldPing_input_host"]
        guard input.waitForExistence(timeout: 5) else {
            XCTFail("Host input not found")
            return
        }
        input.click()
        input.typeText("google.com")
        app.buttons["worldPing_button_run"].click()

        // Network-dependent: skip if no response
        let results = app.staticTexts["worldPing_section_results"]
        if results.waitForExistence(timeout: 30) {
            XCTAssertTrue(
                app.buttons["worldPing_button_clear"].waitForExistence(timeout: 5),
                "Clear button should appear after results"
            )
        } else {
            throw XCTSkip("Network unavailable; skipping results check")
        }
    }
}
