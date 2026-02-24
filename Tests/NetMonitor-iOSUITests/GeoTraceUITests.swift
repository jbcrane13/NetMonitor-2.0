import XCTest

@MainActor
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
            app.textFields["geoTrace_input_host"],
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

        clearAndTypeText("8.8.8.8", into: app.textFields["geoTrace_input_host"])

        let traceButton = app.buttons["geoTrace_button_trace"]
        XCTAssertTrue(traceButton.isEnabled, "Trace button should be enabled with a host")
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
