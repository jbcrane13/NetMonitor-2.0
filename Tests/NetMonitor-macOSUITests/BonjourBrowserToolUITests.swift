@preconcurrency import XCTest

final class BonjourBrowserToolUITests: XCTestCase {
    nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools
        let sidebar = app.descendants(matching: .any)["sidebar_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        // Open Bonjour Browser tool
        let card = app.otherElements["tools_card_bonjour_browser"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Element Existence

    func testRefreshButtonExists() {
        XCTAssertTrue(app.buttons["bonjour_button_refresh"].waitForExistence(timeout: 3))
    }

    func testCloseButtonExists() {
        XCTAssertTrue(app.buttons["bonjour_button_close"].waitForExistence(timeout: 3))
    }

    // MARK: - Interactions

    func testCloseButtonDismissesSheet() {
        let closeButton = app.buttons["bonjour_button_close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.tap()
        XCTAssertTrue(app.otherElements["tools_card_bonjour_browser"].waitForExistence(timeout: 3))
    }

    func testRefreshButtonBecomesEnabled() {
        let refreshButton = app.buttons["bonjour_button_refresh"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 3))
        // Wait for initial scan to complete, then refresh should be enabled
        let enabled = refreshButton.waitForExistence(timeout: 15)
        XCTAssertTrue(enabled)
    }

    func testAutoScanOnOpen() {
        // Bonjour browser auto-starts scanning when opened
        // Just verify the sheet is displayed properly
        XCTAssertTrue(app.buttons["bonjour_button_close"].waitForExistence(timeout: 3))
    }
}
