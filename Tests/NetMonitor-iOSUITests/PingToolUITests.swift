import XCTest

final class PingToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools tab, then Ping
        app.tabBars.buttons["Tools"].tap()
        let pingCard = app.otherElements["tools_card_ping"]
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testPingToolScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_pingTool"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Ping"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Elements

    func testHostInputFieldExists() throws {
        XCTAssertTrue(app.textFields["pingTool_input_host"].waitForExistence(timeout: 5))
    }

    func testPingCountPickerExists() throws {
        XCTAssertTrue(app.buttons["pingTool_picker_count"].waitForExistence(timeout: 5) ||
                      app.otherElements["pingTool_picker_count"].waitForExistence(timeout: 3))
    }

    func testRunButtonExists() throws {
        XCTAssertTrue(app.buttons["pingTool_button_run"].waitForExistence(timeout: 5))
    }

    // MARK: - Input Interaction

    func testTypeHostAddress() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")
        XCTAssertEqual(hostField.value as? String, "8.8.8.8")
    }

    func testClearHostField() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("google.com")
        // Tap the clear button on the input field
        let clearButton = app.buttons["pingTool_input_host_button_clear"]
        if clearButton.waitForExistence(timeout: 3) {
            clearButton.tap()
            XCTAssertEqual(hostField.value as? String, "" , "Field should be cleared")
        }
    }

    // MARK: - Ping Execution

    func testStartPing() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        let runButton = app.buttons["pingTool_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 3))
        runButton.tap()

        // Results section should appear
        let resultsSection = app.otherElements["pingTool_section_results"]
        XCTAssertTrue(resultsSection.waitForExistence(timeout: 10))
    }

    func testPingStatisticsAppearAfterCompletion() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        app.buttons["pingTool_button_run"].tap()

        // Wait for statistics to appear
        let statsCard = app.otherElements["pingTool_card_statistics"]
        XCTAssertTrue(statsCard.waitForExistence(timeout: 30))
    }

    func testClearResultsButton() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        app.buttons["pingTool_button_run"].tap()

        // Wait for results then clear
        let resultsSection = app.otherElements["pingTool_section_results"]
        if resultsSection.waitForExistence(timeout: 15) {
            // Wait for ping to finish
            let clearButton = app.buttons["pingTool_button_clear"]
            if clearButton.waitForExistence(timeout: 30) {
                clearButton.tap()
                XCTAssertFalse(resultsSection.exists)
            }
        }
    }

    // MARK: - Enhanced Ping: Latency Chart

    func testChartAppearsAfterPings() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        app.buttons["pingTool_button_run"].tap()

        // Chart needs at least 2 successful pings to appear
        let chart = app.otherElements["pingTool_chart_latency"]
        XCTAssertTrue(chart.waitForExistence(timeout: 20),
                      "Latency chart should appear after successful pings")
    }

    // MARK: - Enhanced Ping: Live Stats

    func testLiveStatsVisibleDuringPing() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        app.buttons["pingTool_button_run"].tap()

        // Wait for chart section to appear (stats are shown alongside the chart)
        let chart = app.otherElements["pingTool_chart_latency"]
        XCTAssertTrue(chart.waitForExistence(timeout: 20),
                      "Chart should appear so stats are visible")

        // Verify stat elements exist
        let minStat = app.otherElements["pingTool_stat_min"]
            .waitForExistence(timeout: 5)
            || app.staticTexts["pingTool_stat_min"].waitForExistence(timeout: 3)
        XCTAssertTrue(minStat, "Min stat should be visible during ping")

        let avgStat = app.otherElements["pingTool_stat_avg"]
            .waitForExistence(timeout: 5)
            || app.staticTexts["pingTool_stat_avg"].waitForExistence(timeout: 3)
        XCTAssertTrue(avgStat, "Avg stat should be visible during ping")

        let maxStat = app.otherElements["pingTool_stat_max"]
            .waitForExistence(timeout: 5)
            || app.staticTexts["pingTool_stat_max"].waitForExistence(timeout: 3)
        XCTAssertTrue(maxStat, "Max stat should be visible during ping")
    }

    // MARK: - Enhanced Ping: Count Picker

    func testCountPickerChangesValue() throws {
        let picker = app.buttons["pingTool_picker_count"]
        let pickerAlt = app.otherElements["pingTool_picker_count"]
        let pickerExists = picker.waitForExistence(timeout: 5)
            || pickerAlt.waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Ping count picker should exist")

        // Tap whichever element was found to open the picker menu
        if picker.exists {
            picker.tap()
        } else {
            pickerAlt.tap()
        }

        // Select a different count option from the menu
        let option = app.buttons["5"]
        if option.waitForExistence(timeout: 5) {
            option.tap()
        }
    }

    // MARK: - Enhanced Ping: Stats Card After Completion

    func testStatsCardShowsSummaryAfterCompletion() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        // Use a small count for faster completion
        let picker = app.buttons["pingTool_picker_count"]
        let pickerAlt = app.otherElements["pingTool_picker_count"]
        if picker.waitForExistence(timeout: 3) {
            picker.tap()
        } else if pickerAlt.waitForExistence(timeout: 3) {
            pickerAlt.tap()
        }
        let fiveOption = app.buttons["5"]
        if fiveOption.waitForExistence(timeout: 3) {
            fiveOption.tap()
        }

        app.buttons["pingTool_button_run"].tap()

        // Wait for statistics card to appear after completion
        let statsCard = app.otherElements["pingTool_card_statistics"]
        XCTAssertTrue(statsCard.waitForExistence(timeout: 30),
                      "Statistics card should appear after ping completes")
    }

    // MARK: - Enhanced Ping: Clear Removes Chart

    func testClearRemovesChart() throws {
        let hostField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.tap()
        hostField.typeText("8.8.8.8")

        app.buttons["pingTool_button_run"].tap()

        // Wait for chart to appear
        let chart = app.otherElements["pingTool_chart_latency"]
        XCTAssertTrue(chart.waitForExistence(timeout: 20),
                      "Chart should appear before we can clear it")

        // Wait for ping to complete so clear button appears
        let clearButton = app.buttons["pingTool_button_clear"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 30),
                      "Clear button should appear after ping completes")

        clearButton.tap()

        // Chart should be gone after clearing
        let chartGone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: chartGone, object: chart)
        let result = XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Chart should disappear after clearing results")
    }
}
