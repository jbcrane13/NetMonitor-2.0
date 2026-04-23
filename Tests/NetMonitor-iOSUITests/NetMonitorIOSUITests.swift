import XCTest

@MainActor
class NetMonitorIOSUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAppLaunches() throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    // MARK: - Functional Smoke Tests

    func testLaunchShowsDashboardContent() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "App should launch to foreground")

        // FUNCTIONAL: verify the dashboard actually renders content after launch
        let dashboardScreen = app.otherElements["screen_dashboard"]
        XCTAssertTrue(
            dashboardScreen.waitForExistence(timeout: 8),
            "Dashboard screen should be visible after app launch"
        )

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar should be visible after launch")
        XCTAssertTrue(tabBar.buttons["Dashboard"].isSelected, "Dashboard tab should be selected on launch")
    }

    func testLaunchShowsInteractiveElements() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "App should launch to foreground")

        // FUNCTIONAL: verify key interactive elements are present and usable
        let settingsButton = app.buttons["dashboard_button_settings"]
        XCTAssertTrue(
            settingsButton.waitForExistence(timeout: 5),
            "Settings button should be accessible from the dashboard on launch"
        )

        let connectionStatus = app.otherElements["dashboard_label_connectionStatus"]
        let healthCard = app.otherElements["dashboard_card_healthScore"]
        XCTAssertTrue(
            waitForEither([connectionStatus, healthCard], timeout: 8),
            "Dashboard should display connection status or health score card after launch"
        )
    }

    func testAllTabsAccessibleAfterLaunch() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "App should launch to foreground")

        // FUNCTIONAL: verify each tab is tappable and shows its screen
        let tabBar = app.tabBars.firstMatch
        requireExists(tabBar, timeout: 5, message: "Tab bar should exist after launch")

        // Map tab
        tabBar.buttons["Map"].tap()
        XCTAssertTrue(
            app.otherElements["screen_networkMap"].waitForExistence(timeout: 8),
            "Map screen should appear after tapping Map tab"
        )

        // Tools tab
        tabBar.buttons["Tools"].tap()
        XCTAssertTrue(
            app.otherElements["screen_tools"].waitForExistence(timeout: 8),
            "Tools screen should appear after tapping Tools tab"
        )

        // Dashboard tab
        tabBar.buttons["Dashboard"].tap()
        XCTAssertTrue(
            app.otherElements["screen_dashboard"].waitForExistence(timeout: 8),
            "Dashboard screen should appear after tapping Dashboard tab"
        )
    }

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
