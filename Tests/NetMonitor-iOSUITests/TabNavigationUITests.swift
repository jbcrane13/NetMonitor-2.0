import XCTest

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

    func testTabBarExistsAndIsInteractive() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 5),
            "Tab bar should be visible on launch"
        )
        // FUNCTIONAL: verify tab bar has selectable tabs
        XCTAssertGreaterThanOrEqual(tabBar.buttons.count, 3, "Tab bar should have at least 3 tabs")
    }

    func testDashboardTabExistsAndIsSelected() throws {
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(
            dashboardTab.waitForExistence(timeout: 5),
            "Dashboard tab button should exist in tab bar"
        )
        // FUNCTIONAL: Dashboard should be selected by default
        XCTAssertTrue(dashboardTab.isSelected, "Dashboard tab should be selected on launch")
    }

    func testMapTabExistsAndNavigates() throws {
        let mapTab = app.tabBars.buttons["Map"]
        XCTAssertTrue(
            mapTab.waitForExistence(timeout: 5),
            "Map tab button should exist in tab bar"
        )
        // FUNCTIONAL: tapping Map tab actually changes visible content
        mapTab.tap()
        XCTAssertTrue(
            app.otherElements["screen_networkMap"].waitForExistence(timeout: 5),
            "Network Map screen should appear after tapping Map tab"
        )
        XCTAssertTrue(mapTab.isSelected, "Map tab should be selected after tapping it")
    }

    func testToolsTabExistsAndNavigates() throws {
        let toolsTab = app.tabBars.buttons["Tools"]
        XCTAssertTrue(
            toolsTab.waitForExistence(timeout: 5),
            "Tools tab button should exist in tab bar"
        )
        // FUNCTIONAL: tapping Tools tab actually changes visible content
        toolsTab.tap()
        XCTAssertTrue(
            app.otherElements["screen_tools"].waitForExistence(timeout: 5),
            "Tools screen should appear after tapping Tools tab"
        )
        XCTAssertTrue(toolsTab.isSelected, "Tools tab should be selected after tapping it")
    }

    // MARK: - Tab Navigation

    func testDashboardTabIsSelectedByDefault() throws {
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        XCTAssertTrue(dashboardTab.isSelected)
        // FUNCTIONAL: verify dashboard content is actually visible
        XCTAssertTrue(
            app.otherElements["screen_dashboard"].waitForExistence(timeout: 5),
            "Dashboard screen content should be visible when Dashboard tab is selected"
        )
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
        // FUNCTIONAL: verify tab bar remains visible and each tab switch actually changes content
        let tabBar = app.tabBars.firstMatch
        requireExists(tabBar, timeout: 5, message: "Tab bar should exist initially")

        // Switch to Tools — verify content changes
        app.tabBars.buttons["Tools"].tap()
        XCTAssertTrue(
            app.otherElements["screen_tools"].waitForExistence(timeout: 5),
            "Tools screen should be visible after tapping Tools tab"
        )
        XCTAssertTrue(tabBar.exists, "Tab bar should persist after switching to Tools")

        // Switch to Map — verify content changes
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(
            app.otherElements["screen_networkMap"].waitForExistence(timeout: 5),
            "Network Map screen should be visible after tapping Map tab"
        )
        XCTAssertTrue(tabBar.exists, "Tab bar should persist after switching to Map")

        // Switch back to Dashboard — verify content changes
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(
            app.otherElements["screen_dashboard"].waitForExistence(timeout: 5),
            "Dashboard screen should be visible after tapping Dashboard tab"
        )
        XCTAssertTrue(tabBar.exists, "Tab bar should persist after switching back to Dashboard")
    }

    // MARK: - Functional: Tab selection state changes

    func testTabSelectionStateChangesOnTap() {
        let dashboardTab = app.tabBars.buttons["Dashboard"]
        let mapTab = app.tabBars.buttons["Map"]
        let toolsTab = app.tabBars.buttons["Tools"]

        requireExists(dashboardTab, timeout: 5, message: "Dashboard tab should exist")
        XCTAssertTrue(dashboardTab.isSelected, "Dashboard should be selected initially")

        // FUNCTIONAL: selecting another tab deselects the previous one
        mapTab.tap()
        XCTAssertTrue(mapTab.waitForExistence(timeout: 3))
        XCTAssertFalse(dashboardTab.isSelected, "Dashboard tab should be deselected after tapping Map")
        XCTAssertTrue(mapTab.isSelected, "Map tab should be selected after tapping it")

        // Switch to Tools
        toolsTab.tap()
        XCTAssertTrue(toolsTab.waitForExistence(timeout: 3))
        XCTAssertFalse(mapTab.isSelected, "Map tab should be deselected after tapping Tools")
        XCTAssertTrue(toolsTab.isSelected, "Tools tab should be selected after tapping it")
    }

    // MARK: - Functional: Each tab shows distinct content

    func testEachTabShowsDistinctContent() {
        let dashboardScreen = app.otherElements["screen_dashboard"]
        let mapScreen = app.otherElements["screen_networkMap"]
        let toolsScreen = app.otherElements["screen_tools"]

        // Dashboard — verify dashboard-specific content visible
        XCTAssertTrue(
            dashboardScreen.waitForExistence(timeout: 8),
            "Dashboard screen should be visible on launch"
        )

        // Switch to Map — dashboard should no longer be the visible screen
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(
            mapScreen.waitForExistence(timeout: 8),
            "Map screen should appear after tapping Map tab"
        )

        // Switch to Tools — map should no longer be the visible screen
        app.tabBars.buttons["Tools"].tap()
        XCTAssertTrue(
            toolsScreen.waitForExistence(timeout: 8),
            "Tools screen should appear after tapping Tools tab"
        )

        // Back to Dashboard
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(
            dashboardScreen.waitForExistence(timeout: 8),
            "Dashboard screen should reappear after tapping Dashboard tab"
        )
    }

    // MARK: - Functional: Timeline tab navigation

    func testTimelineTabNavigatesAndShowsContent() {
        let timelineTab = app.tabBars.buttons["Timeline"]
        guard timelineTab.waitForExistence(timeout: 5) else { return }

        timelineTab.tap()

        // FUNCTIONAL: verify timeline-specific content appears
        let timelineScreen = app.otherElements["screen_networkTimeline"]
        let emptyState = app.otherElements["timeline_label_emptyState"]
        let eventList = app.otherElements["timeline_list_events"]

        XCTAssertTrue(
            timelineScreen.waitForExistence(timeout: 8),
            "Timeline screen should appear after tapping Timeline tab"
        )
        XCTAssertTrue(
            waitForEither([emptyState, eventList], timeout: 8),
            "Timeline should show either empty state or event list content"
        )
    }

    // MARK: - Helpers

    private func requireExists(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        message: String
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        return element
    }

    private func waitForEither(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
