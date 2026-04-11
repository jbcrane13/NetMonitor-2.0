import XCTest

@MainActor
final class TabNavigationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tab Bar Existence

    func testTabBarExists() throws {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testDashboardTabExists() throws {
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].exists)
    }

    func testMapTabExists() throws {
        XCTAssertTrue(app.tabBars.buttons["Map"].exists)
    }

    func testToolsTabExists() throws {
        XCTAssertTrue(app.tabBars.buttons["Tools"].exists)
    }

    // MARK: - Tab Navigation

    func testDashboardTabIsSelectedByDefault() throws {
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboardTab.isSelected)
    }

    func testNavigateToMapTab() throws {
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.otherElements["screen_networkMap"].waitForExistence(timeout: 5))
    }

    func testNavigateToToolsTab() throws {
        app.tabBars.buttons["Tools"].tap()
        XCTAssertTrue(app.otherElements["screen_tools"].waitForExistence(timeout: 5))
    }

    func testNavigateBackToDashboard() throws {
        app.tabBars.buttons["Tools"].tap()
        XCTAssertTrue(app.otherElements["screen_tools"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.otherElements["screen_dashboard"].waitForExistence(timeout: 5))
    }

    func testCycleThroughAllTabs() throws {
        // Dashboard -> Map
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.otherElements["screen_networkMap"].waitForExistence(timeout: 5))

        // Map -> Tools
        app.tabBars.buttons["Tools"].tap()
        XCTAssertTrue(app.otherElements["screen_tools"].waitForExistence(timeout: 5))

        // Tools -> Dashboard
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.otherElements["screen_dashboard"].waitForExistence(timeout: 5))
    }

    func testTabBarPersistsAcrossNavigation() throws {
        app.tabBars.buttons["Tools"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.exists)

        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.exists)

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }
}
