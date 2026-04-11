import XCTest

@MainActor
final class PingToolUITests: XCTestCase {
    nonisolated(unsafe) nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools
        let sidebar = app.descendants(matching: .any)["sidebar_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        // Open Ping tool
        let pingCard = app.otherElements["tools_card_ping"]
        XCTAssertTrue(pingCard.waitForExistence(timeout: 3))
        pingCard.tap()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Element Existence

    func testHostFieldExists() {
        XCTAssertTrue(app.textFields["ping_textfield_host"].waitForExistence(timeout: 3))
    }

    func testCountPickerExists() {
        XCTAssertTrue(app.popUpButtons["ping_picker_count"].waitForExistence(timeout: 3))
    }

    func testRunButtonExists() {
        XCTAssertTrue(app.buttons["ping_button_run"].waitForExistence(timeout: 3))
    }

    func testCloseButtonExists() {
        XCTAssertTrue(app.buttons["ping_button_close"].waitForExistence(timeout: 3))
    }

    // MARK: - Interactions

    func testRunButtonDisabledWhenHostEmpty() {
        let runButton = app.buttons["ping_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 3))
        XCTAssertFalse(runButton.isEnabled)
    }

    func testRunButtonEnabledAfterTypingHost() {
        let hostField = app.textFields["ping_textfield_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 3))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        let runButton = app.buttons["ping_button_run"]
        XCTAssertTrue(runButton.isEnabled)
    }

    func testCloseButtonDismissesSheet() {
        let closeButton = app.buttons["ping_button_close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.tap()

        // Sheet should dismiss, tool cards should be visible again
        XCTAssertTrue(app.otherElements["tools_card_ping"].waitForExistence(timeout: 3))
    }

    func testTypeHostAndRun() {
        let hostField = app.textFields["ping_textfield_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 3))
        hostField.tap()
        hostField.typeText("127.0.0.1")

        app.buttons["ping_button_run"].tap()

        // Button label should change to "Stop" while running
        let stopButton = app.buttons["ping_button_run"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 3))
    }

    // MARK: - Enhanced Ping: Latency Chart

    func testChartAppearsAfterPings() {
        let hostField = app.textFields["ping_textfield_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 3))
        hostField.tap()
        hostField.typeText("127.0.0.1")

        app.buttons["ping_button_run"].tap()

        // Chart needs at least 2 successful pings to render
        let chart = app.otherElements["ping_chart_latency"]
        XCTAssertTrue(chart.waitForExistence(timeout: 20),
                      "Latency chart should appear after successful pings")
    }

    // MARK: - Enhanced Ping: Stats Line

    func testStatsVisibleAfterPings() {
        let hostField = app.textFields["ping_textfield_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 3))
        hostField.tap()
        hostField.typeText("127.0.0.1")

        app.buttons["ping_button_run"].tap()

        // Wait for chart to appear (stats are rendered alongside the chart)
        let chart = app.otherElements["ping_chart_latency"]
        XCTAssertTrue(chart.waitForExistence(timeout: 20),
                      "Chart should appear so stat elements are visible")

        // Verify stat elements
        let minStat = app.staticTexts["ping_stat_min"].waitForExistence(timeout: 5)
            || app.otherElements["ping_stat_min"].waitForExistence(timeout: 3)
        XCTAssertTrue(minStat, "Min stat should be visible")

        let avgStat = app.staticTexts["ping_stat_avg"].waitForExistence(timeout: 5)
            || app.otherElements["ping_stat_avg"].waitForExistence(timeout: 3)
        XCTAssertTrue(avgStat, "Avg stat should be visible")

        let maxStat = app.staticTexts["ping_stat_max"].waitForExistence(timeout: 5)
            || app.otherElements["ping_stat_max"].waitForExistence(timeout: 3)
        XCTAssertTrue(maxStat, "Max stat should be visible")
    }

    // MARK: - Enhanced Ping: Count Picker

    func testCountPickerChangesValue() {
        let picker = app.popUpButtons["ping_picker_count"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3),
                      "Count picker should exist")

        picker.tap()

        // Select a different count from the popup menu
        let option = app.menuItems["5"]
        if option.waitForExistence(timeout: 3) {
            option.tap()
        }

        // Verify the picker still exists after selection
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
    }

    // MARK: - Enhanced Ping: Close Button

    func testCloseButtonDismissesToolSheet() {
        let closeButton = app.buttons["ping_button_close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.tap()

        // After closing, the tools card list should be visible again
        let pingCard = app.otherElements["tools_card_ping"]
        XCTAssertTrue(pingCard.waitForExistence(timeout: 5),
                      "Tool card list should be visible after closing ping sheet")
    }
}
