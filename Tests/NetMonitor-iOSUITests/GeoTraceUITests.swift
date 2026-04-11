@preconcurrency import XCTest

final class GeoTraceUITests: IOSUITestCase {

    func testGeoTraceScreenOpensFromToolsGrid() {
        openGeoTrace()
        requireExists(
            app.descendants(matching: .any)["screen_geoTrace"],
            timeout: 8,
            message: "Geo Trace screen should open from tools grid"
        )
    }

    func testGeoTraceHasInputAndTraceButton() {
        openGeoTrace()

        requireExists(
            app.textFields["geoTrace_textfield_host"],
            message: "Host input field should be visible"
        )

        requireExists(
            app.buttons["geoTrace_button_trace"],
            message: "Trace button should be visible"
        )
    }

    func testGeoTraceMapIsVisible() {
        openGeoTrace()

        requireExists(
            app.descendants(matching: .any)["geoTrace_map"],
            timeout: 8,
            message: "Map view should be visible"
        )
    }

    func testGeoTraceButtonDisabledWithEmptyHost() {
        openGeoTrace()

        // Trace button should be disabled when host is empty
        let traceButton = app.buttons["geoTrace_button_trace"]
        requireExists(traceButton, message: "Trace button should exist")
        XCTAssertFalse(traceButton.isEnabled, "Trace button should be disabled with empty host")
    }

    func testGeoTraceButtonEnabledAfterHostEntry() {
        openGeoTrace()

        clearAndTypeText("8.8.8.8", into: app.textFields["geoTrace_textfield_host"])

        let traceButton = app.buttons["geoTrace_button_trace"]
        XCTAssertTrue(traceButton.isEnabled, "Trace button should be enabled with a host")
    }

    func testGeoTraceTriggersTraceAndShowsOutcome() {
        openGeoTrace()
        clearAndTypeText("8.8.8.8", into: app.textFields["geoTrace_textfield_host"])
        app.buttons["geoTrace_button_trace"].tap()

        // After tap, verify either:
        // - Stop button appears (trace is running)
        // - Hop annotations appear on map
        // - Error message appears (network unavailable on simulator)
        // - Results section appears
        let stopButton = app.buttons["geoTrace_button_stop"]
        let hopAnnotation = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'geoTrace_hop_'")
        ).firstMatch
        let errorLabel = app.descendants(matching: .any)["geoTrace_error"]
        let resultsSection = app.descendants(matching: .any)["geoTrace_results"]
        let anyOutcome = app.staticTexts.matching(NSPredicate(format:
            "label CONTAINS[c] 'hop' OR label CONTAINS[c] 'error' OR label CONTAINS[c] 'unreachable' OR label CONTAINS[c] 'timeout'"
        )).firstMatch

        let deadline = Date().addingTimeInterval(15)
        var outcomeFound = false
        while Date() < deadline {
            if stopButton.exists || hopAnnotation.exists || errorLabel.exists ||
               resultsSection.exists || anyOutcome.exists {
                outcomeFound = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTAssertTrue(outcomeFound, "Geo trace should produce a visible outcome after tapping Trace")
    }

    func testGeoTraceClearRemovesResults() {
        openGeoTrace()
        clearAndTypeText("1.1.1.1", into: app.textFields["geoTrace_textfield_host"])
        app.buttons["geoTrace_button_trace"].tap()

        // Wait briefly for some outcome (running, results, or error)
        RunLoop.current.run(until: Date().addingTimeInterval(3.0))

        // Look for clear button and tap it
        let clearButton = app.buttons.matching(NSPredicate(format:
            "identifier CONTAINS 'clear' OR label CONTAINS[c] 'Clear'"
        )).firstMatch

        guard clearButton.waitForExistence(timeout: 5) else { return }
        clearButton.tap()

        // After clear, results/hops should be gone and input should be empty or reset
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let resultsSection = app.descendants(matching: .any)["geoTrace_results"]
        let hopAnnotation = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'geoTrace_hop_'")
        ).firstMatch

        XCTAssertFalse(resultsSection.exists, "Results should be removed after clear")
        XCTAssertFalse(hopAnnotation.exists, "Hop annotations should be removed after clear")
    }

    // MARK: - Helpers

    private func openGeoTrace() {
        requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist").tap()
        requireExists(
            app.descendants(matching: .any)["screen_tools"],
            timeout: 8,
            message: "Tools root should be visible"
        )

        let card = app.descendants(matching: .any)["tools_card_geo_trace"]
        scrollToElement(card)
        requireExists(card, timeout: 8, message: "Geo Trace tool card should exist").tap()
    }
}
