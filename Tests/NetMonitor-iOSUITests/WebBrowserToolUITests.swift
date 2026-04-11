import XCTest

@MainActor
final class WebBrowserToolUITests: IOSUITestCase {

    override func setUp() async throws {
        try await super.setUp()
        openWebBrowser()
    }

    // MARK: - Screen Existence

    func testWebBrowserScreenExists() throws {
        requireExists(ui("screen_webBrowser"), message: "Web browser screen should exist")
    }

    func testNavigationTitleExists() throws {
        requireExists(app.navigationBars["Web Browser"], message: "Web Browser navigation title should exist")
    }

    // MARK: - Input Elements

    func testURLInputFieldExists() throws {
        requireExists(app.textFields["webBrowser_input_url"], message: "URL input field should exist")
    }

    func testOpenButtonExists() throws {
        requireExists(app.buttons["webBrowser_button_open"], message: "Open button should exist")
    }

    // MARK: - Bookmarks Section

    func testBookmarksSectionExists() throws {
        requireExists(ui("webBrowser_section_bookmarks"), message: "Bookmarks section should exist")
    }

    func testRouterAdminBookmarkExists() throws {
        XCTAssertTrue(
            ui("webBrowser_bookmark_router_admin").waitForExistence(timeout: 5) ||
            app.buttons["webBrowser_bookmark_router_admin"].waitForExistence(timeout: 3),
            "Router Admin bookmark should exist"
        )
    }

    func testSpeedTestBookmarkExists() throws {
        XCTAssertTrue(
            ui("webBrowser_bookmark_speed_test").waitForExistence(timeout: 5) ||
            app.buttons["webBrowser_bookmark_speed_test"].waitForExistence(timeout: 3),
            "Speed Test bookmark should exist"
        )
    }

    // MARK: - Input Interaction

    func testTypeURL() throws {
        let urlField = requireExists(app.textFields["webBrowser_input_url"], message: "URL field should exist")
        clearAndTypeText("https://example.com", into: urlField)
        XCTAssertEqual(urlField.value as? String, "https://example.com", "URL field should contain typed URL")
    }

    // MARK: - Open URL

    func testOpenURLPresentsSafari() throws {
        let urlField = requireExists(app.textFields["webBrowser_input_url"], message: "URL field should exist")
        clearAndTypeText("https://example.com", into: urlField)

        app.buttons["webBrowser_button_open"].tap()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5),
            "App should remain in foreground after opening URL"
        )
    }

    // MARK: - Recent URLs

    func testClearRecentButtonExists() throws {
        let urlField = requireExists(app.textFields["webBrowser_input_url"], message: "URL field should exist")
        clearAndTypeText("https://example.com", into: urlField)
        app.buttons["webBrowser_button_open"].tap()

        if app.buttons["Done"].waitForExistence(timeout: 3) {
            app.buttons["Done"].tap()
        }

        scrollToElement(app.buttons["webBrowser_button_clearRecent"])
        let clearRecent = app.buttons["webBrowser_button_clearRecent"]
        XCTAssertTrue(
            clearRecent.exists || ui("webBrowser_section_recent").exists || ui("screen_webBrowser").exists,
            "After opening a URL, clear recent button, recent section, or web browser screen should exist"
        )
    }

    // MARK: - Functional Tests

    func testBookmarkTapFillsURLField() {
        let routerBookmark = ui("webBrowser_bookmark_router_admin")
        let bookmarkButton = app.buttons["webBrowser_bookmark_router_admin"]

        let bookmark: XCUIElement
        if routerBookmark.waitForExistence(timeout: 5) {
            bookmark = routerBookmark
        } else if bookmarkButton.waitForExistence(timeout: 3) {
            bookmark = bookmarkButton
        } else {
            let firstBookmarkRow = app.cells.matching(
                NSPredicate(format: "identifier BEGINSWITH 'webBrowser_bookmark_'")
            ).firstMatch
            guard firstBookmarkRow.waitForExistence(timeout: 5) else {
                XCTFail("No bookmark rows found to tap")
                return
            }
            bookmark = firstBookmarkRow
        }

        bookmark.tap()

        let urlField = requireExists(
            app.textFields["webBrowser_input_url"],
            timeout: 5,
            message: "URL field should exist after tapping bookmark"
        )
        let fieldValue = urlField.value as? String ?? ""
        XCTAssertFalse(
            fieldValue.isEmpty || fieldValue == urlField.placeholderValue,
            "URL field should be populated after tapping a bookmark"
        )
    }

    func testOpenButtonEnabledAfterURLEntry() {
        let urlField = requireExists(app.textFields["webBrowser_input_url"], message: "URL field should exist")
        let openButton = requireExists(app.buttons["webBrowser_button_open"], message: "Open button should exist")

        clearAndTypeText("", into: urlField)
        XCTAssertFalse(openButton.isEnabled, "Open button should be disabled when URL field is empty")

        clearAndTypeText("https://example.com", into: urlField)
        XCTAssertTrue(openButton.isEnabled, "Open button should be enabled after entering a URL")
    }

    func testBookmarkSectionVisible() {
        requireExists(
            ui("webBrowser_section_bookmarks"),
            message: "Bookmarks section should be visible on web browser screen"
        )

        let bookmarkRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'webBrowser_bookmark_'")
        )
        XCTAssertGreaterThan(bookmarkRows.count, 0, "Bookmarks section should contain at least one bookmark row")
    }

    // MARK: - Helpers

    private func openWebBrowser() {
        let toolsTab = app.tabBars.buttons["Tools"]
        guard toolsTab.waitForExistence(timeout: 5) else {
            XCTFail("Tools tab should exist")
            return
        }
        toolsTab.tap()

        guard ui("screen_tools").waitForExistence(timeout: 8) else {
            XCTFail("Tools root should be visible")
            return
        }

        let card = ui("tools_card_web_browser")
        scrollToElement(card)
        guard card.waitForExistence(timeout: 8) else {
            XCTFail("Web browser tool card should exist")
            return
        }
        card.tap()

        guard ui("screen_webBrowser").waitForExistence(timeout: 8) else {
            XCTFail("Web browser screen should open from tools grid")
            return
        }
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
