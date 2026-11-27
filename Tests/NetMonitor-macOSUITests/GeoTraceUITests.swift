import XCTest

@MainActor
final class GeoTraceUITests: MacOSUITestCase {

    func testGeoTraceOpensFromToolsGrid() {
        openGeoTrace()
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
            ui("geoTrace_label_map").firstMatch,
            timeout: 8,
            message: "Map should be visible in Geo Trace sheet"
        )
    }

    func testGeoTraceTraceButtonDisabledWhenEmpty() {
        openGeoTrace()

        let traceButton = app.buttons["geoTrace_button_trace"]
        requireExists(traceButton, message: "Trace button should exist")
        XCTAssertFalse(traceButton.isEnabled, "Trace button should be disabled when host is empty")
    }

    // MARK: - Helpers

    private func openGeoTrace() {
        navigateToSidebar("tools")
        let toolsCard = ui("tools_card_geo_trace").firstMatch
        requireExists(toolsCard, timeout: 8, message: "Geo Trace tool card should exist in grid").click()

        requireExists(
            ui("geoTrace_label_map").firstMatch,
            timeout: 8,
            message: "Geo Trace sheet should open with map visible"
        )
    }
}
