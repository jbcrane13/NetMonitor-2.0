import XCTest

@MainActor
final class BonjourBrowserToolUITests: MacOSUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        openTool(cardID: "tools_card_bonjour_browser", sheetElement: "bonjour_button_close")
    }

    // MARK: - Element Existence

    func testRefreshButtonExists() {
        XCTAssertTrue(app.buttons["bonjour_button_refresh"].waitForExistence(timeout: 3))
    }

    func testCloseButtonExists() {
        XCTAssertTrue(app.buttons["bonjour_button_close"].waitForExistence(timeout: 3))
    }

    // MARK: - Interactions

    func testCloseButtonDismissesSheet() {
        closeTool(closeButtonID: "bonjour_button_close", cardID: "tools_card_bonjour_browser")
    }

    func testRefreshButtonBecomesEnabled() {
        let refreshButton = app.buttons["bonjour_button_refresh"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 3))
        // The initial scan stops itself after 10 seconds, then Refresh is enabled again.
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: refreshButton)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 15), .completed,
                       "Refresh should be enabled once the initial scan finishes")
    }

    func testAutoScanOnOpen() {
        // Bonjour browser auto-starts scanning when opened
        // Just verify the sheet is displayed properly
        XCTAssertTrue(app.buttons["bonjour_button_close"].waitForExistence(timeout: 3))
    }
}
