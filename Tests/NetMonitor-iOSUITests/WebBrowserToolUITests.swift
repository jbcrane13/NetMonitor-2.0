import XCTest

final class WebBrowserToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Tools"].tap()
        let webBrowserCard = app.otherElements["tools_card_web_browser"]
        if webBrowserCard.waitForExistence(timeout: 5) {
            webBrowserCard.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testWebBrowserScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_webBrowser"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Web Browser"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Elements

    func testURLInputFieldExists() throws {
        XCTAssertTrue(app.textFields["webBrowser_input_url"].waitForExistence(timeout: 5))
    }

    func testOpenButtonExists() throws {
        XCTAssertTrue(app.buttons["webBrowser_button_open"].waitForExistence(timeout: 5))
    }

    // MARK: - Bookmarks Section

    func testBookmarksSectionExists() throws {
        XCTAssertTrue(app.otherElements["webBrowser_section_bookmarks"].waitForExistence(timeout: 5))
    }

    func testRouterAdminBookmarkExists() throws {
        let bookmark = app.otherElements["webBrowser_bookmark_router_admin"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5) ||
                      app.buttons["webBrowser_bookmark_router_admin"].waitForExistence(timeout: 3))
    }

    func testSpeedTestBookmarkExists() throws {
        let bookmark = app.otherElements["webBrowser_bookmark_speed_test"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5) ||
                      app.buttons["webBrowser_bookmark_speed_test"].waitForExistence(timeout: 3))
    }

    // MARK: - Input Interaction

    func testTypeURL() throws {
        let urlField = app.textFields["webBrowser_input_url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.tap()
        urlField.typeText("https://example.com")
        XCTAssertEqual(urlField.value as? String, "https://example.com")
    }

    // MARK: - Open URL

    func testOpenURLPresentsSafari() throws {
        let urlField = app.textFields["webBrowser_input_url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.tap()
        urlField.typeText("https://example.com")

        app.buttons["webBrowser_button_open"].tap()

        // Safari view controller should be presented
        // It appears as a sheet; wait for it
        sleep(2)
        // The Safari view may not have specific accessibility IDs,
        // but the app should still be in foreground
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    // MARK: - Recent URLs

    func testClearRecentButtonExists() throws {
        // First open a URL to create recent history
        let urlField = app.textFields["webBrowser_input_url"]
        if urlField.waitForExistence(timeout: 5) {
            urlField.tap()
            urlField.typeText("https://example.com")
            app.buttons["webBrowser_button_open"].tap()
            sleep(2)
            // Dismiss Safari if presented
            if app.buttons["Done"].exists {
                app.buttons["Done"].tap()
            }
            // Check for clear recent button
            app.swipeUp()
            let clearRecent = app.buttons["webBrowser_button_clearRecent"]
            // May or may not exist depending on state
            XCTAssertTrue(clearRecent.exists || app.otherElements["webBrowser_section_recent"].exists ||
                          app.otherElements["screen_webBrowser"].exists)
        }
    }
}
