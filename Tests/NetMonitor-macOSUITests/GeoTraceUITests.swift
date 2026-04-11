@preconcurrency import XCTest

final class GeoTraceUITests: MacOSUITestCase {

    func testGeoTraceOpensFromToolsGrid() {
        openGeoTrace()
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
        let toolsCard = app.descendants(matching: .any)["tools_card_geo_trace"]
        scrollToElement(toolsCard)
        requireExists(toolsCard, timeout: 8, message: "Geo Trace tool card should exist in grid").tap()

        requireExists(
            app.descendants(matching: .any)["geoTrace_map"],
            timeout: 8,
            message: "Geo Trace sheet should open with map visible"
        )
    }

    private func scrollToElement(_ element: XCUIElement, maxScrolls: Int = 5) {
        guard !element.exists else { return }
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<maxScrolls {
            if element.exists { return }
            scroll.swipeUp()
        }
    }
}
