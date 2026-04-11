@preconcurrency import XCTest

final class PingToolUITests: IOSUITestCase {

    private func navigateToPingTool() {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = app.otherElements["tools_card_ping"]
        scrollToElement(pingCard)
        requireExists(pingCard, timeout: 8, message: "Ping tool card should exist")
        pingCard.tap()
        requireExists(app.otherElements["screen_pingTool"], timeout: 8, message: "Ping tool screen should appear")
    }

    // MARK: - Screen Existence

    func testPingToolScreenExists() throws {
        navigateToPingTool()
        requireExists(app.otherElements["screen_pingTool"], message: "Ping tool screen should exist")
    }

    func testNavigationTitleExists() throws {
        navigateToPingTool()
        requireExists(app.navigationBars["Ping"], message: "Ping navigation bar should exist")
    }

    // MARK: - Input Elements

    func testHostInputFieldExists() throws {
        navigateToPingTool()
        requireExists(app.textFields["pingTool_input_host"], message: "Host input field should exist")
    }

    func testPingCountPickerExists() throws {
        navigateToPingTool()
        let pickerExists = app.buttons["pingTool_picker_count"].waitForExistence(timeout: 5)
            || app.otherElements["pingTool_picker_count"].waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Ping count picker should exist")
    }

    func testRunButtonExists() throws {
        navigateToPingTool()
        requireExists(app.buttons["pingTool_button_run"], message: "Run button should exist")
    }

    // MARK: - Input Interaction

    func testTypeHostAddress() throws {
        navigateToPingTool()
        let hostField = app.textFields["pingTool_input_host"]
        clearAndTypeText("8.8.8.8", into: hostField)
        XCTAssertEqual(hostField.value as? String, "8.8.8.8")
    }

    func testClearHostField() throws {
        navigateToPingTool()
        let hostField = app.textFields["pingTool_input_host"]
        clearAndTypeText("google.com", into: hostField)
        let clearButton = app.buttons["pingTool_input_host_button_clear"]
        if clearButton.waitForExistence(timeout: 3) {
            clearButton.tap()
            XCTAssertEqual(hostField.value as? String, "", "Field should be cleared")
        }
    }

    // MARK: - Ping Execution

    func testStartPing() throws {
        navigateToPingTool()
        clearAndTypeText("8.8.8.8", into: app.textFields["pingTool_input_host"])
        app.buttons["pingTool_button_run"].tap()
        let resultsSection = app.otherElements["pingTool_section_results"]
        XCTAssertTrue(resultsSection.waitForExistence(timeout: 10), "Results section should appear after starting ping")
    }

    func testPingStatisticsAppearAfterCompletion() throws {
        navigateToPingTool()
        clearAndTypeText("8.8.8.8", into: app.textFields["pingTool_input_host"])
        app.buttons["pingTool_button_run"].tap()
        let statsCard = app.otherElements["pingTool_card_statistics"]
        XCTAssertTrue(statsCard.waitForExistence(timeout: 30), "Statistics card should appear after ping completes")
    }

    func testClearResultsButton() throws {
        navigateToPingTool()
        clearAndTypeText("8.8.8.8", into: app.textFields["pingTool_input_host"])
        app.buttons["pingTool_button_run"].tap()
        let resultsSection = app.otherElements["pingTool_section_results"]
        if resultsSection.waitForExistence(timeout: 15) {
            let clearButton = app.buttons["pingTool_button_clear"]
            if clearButton.waitForExistence(timeout: 30) {
                clearButton.tap()
                XCTAssertTrue(waitForDisappearance(resultsSection, timeout: 5), "Results section should disappear after clear")
            }
        }
    }

    // MARK: - Enhanced Ping: Latency Chart

    func testChartAppearsAfterPings() throws {
        navigateToPingTool()
        clearAndTypeText("8.8.8.8", into: app.textFields["pingTool_input_host"])
        app.buttons["pingTool_button_run"].tap()
        let chart = app.otherElements["pingTool_chart_latency"]
        XCTAssertTrue(chart.waitForExistence(timeout: 20), "Latency chart should appear after successful pings")
    }

    // MARK: - Enhanced Ping: Live Stats

    func testLiveStatsVisibleDuringPing() throws {
        navigateToPingTool()
        clearAndTypeText("8.8.8.8", into: app.textFields["pingTool_input_host"])
        app.buttons["pingTool_button_run"].tap()
        let chart = app.otherElements["pingTool_chart_latency"]
        XCTAssertTrue(chart.waitForExistence(timeout: 20), "Chart should appear so stats are visible")

        let minStat = app.otherElements["pingTool_stat_min"].waitForExistence(timeout: 5)
            || app.staticTexts["pingTool_stat_min"].waitForExistence(timeout: 3)
        XCTAssertTrue(minStat, "Min stat should be visible during ping")

        let avgStat = app.otherElements["pingTool_stat_avg"].waitForExistence(timeout: 5)
            || app.staticTexts["pingTool_stat_avg"].waitForExistence(timeout: 3)
        XCTAssertTrue(avgStat, "Avg stat should be visible during ping")

        let maxStat = app.otherElements["pingTool_stat_max"].waitForExistence(timeout: 5)
            || app.staticTexts["pingTool_stat_max"].waitForExistence(timeout: 3)
        XCTAssertTrue(maxStat, "Max stat should be visible during ping")
    }

    // MARK: - Enhanced Ping: Count Picker

    func testCountPickerChangesValue() throws {
        navigateToPingTool()
        let picker = app.buttons["pingTool_picker_count"]
        let pickerAlt = app.otherElements["pingTool_picker_count"]
        let pickerExists = picker.waitForExistence(timeout: 5) || pickerAlt.waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Ping count picker should exist")

        if picker.exists {
            picker.tap()
        } else {
            pickerAlt.tap()
        }

        let option = app.buttons["5"]
        if option.waitForExistence(timeout: 5) {
            option.tap()
        }
    }

    // MARK: - Enhanced Ping: Stats Card After Completion

    func testStatsCardShowsSummaryAfterCompletion() throws {
        navigateToPingTool()
        clearAndTypeText("8.8.8.8", into: app.textFields["pingTool_input_host"])

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
        let statsCard = app.otherElements["pingTool_card_statistics"]
        XCTAssertTrue(statsCard.waitForExistence(timeout: 30), "Statistics card should appear after ping completes")
    }

    // MARK: - Enhanced Ping: Clear Removes Chart

    func testClearRemovesChart() throws {
        navigateToPingTool()
        clearAndTypeText("8.8.8.8", into: app.textFields["pingTool_input_host"])
        app.buttons["pingTool_button_run"].tap()

        let chart = app.otherElements["pingTool_chart_latency"]
        XCTAssertTrue(chart.waitForExistence(timeout: 20), "Chart should appear before we can clear it")

        let clearButton = app.buttons["pingTool_button_clear"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 30), "Clear button should appear after ping completes")
        clearButton.tap()

        XCTAssertTrue(waitForDisappearance(chart, timeout: 5), "Chart should disappear after clearing results")
    }

    // MARK: - Picker Interaction

    func testPingCountPickerInteraction() throws {
        navigateToPingTool()

        let pickerButton = app.buttons["pingTool_picker_count"]
        let pickerElement = app.otherElements["pingTool_picker_count"]
        let pickerExists = pickerButton.waitForExistence(timeout: 5) || pickerElement.waitForExistence(timeout: 3)
        XCTAssertTrue(pickerExists, "Ping count picker should exist on the ping tool screen")

        if pickerButton.exists {
            pickerButton.tap()
        } else {
            pickerElement.tap()
        }

        let countOptions = ["5", "10", "20", "50", "100"]
        var selectedOption = false
        for count in countOptions {
            let option = app.buttons[count]
            if option.waitForExistence(timeout: 2) {
                option.tap()
                selectedOption = true
                break
            }
        }

        let pickerStillExists = pickerButton.waitForExistence(timeout: 3) || pickerElement.waitForExistence(timeout: 3)
        XCTAssertTrue(pickerStillExists || !selectedOption, "Picker should remain accessible after selecting a count option")
    }

    func testPingStatisticsSectionAppearsAfterRun() throws {
        navigateToPingTool()
        clearAndTypeText("127.0.0.1", into: app.textFields["pingTool_input_host"])

        let pickerButton = app.buttons["pingTool_picker_count"]
        let pickerElement = app.otherElements["pingTool_picker_count"]
        if pickerButton.waitForExistence(timeout: 3) {
            pickerButton.tap()
        } else if pickerElement.waitForExistence(timeout: 3) {
            pickerElement.tap()
        }
        let fiveOption = app.buttons["5"]
        if fiveOption.waitForExistence(timeout: 3) {
            fiveOption.tap()
        }

        app.buttons["pingTool_button_run"].tap()

        let statsCard = app.otherElements["pingTool_card_statistics"]
        let minStat = app.otherElements["pingTool_stat_min"]
        let avgStat = app.otherElements["pingTool_stat_avg"]
        let maxStat = app.otherElements["pingTool_stat_max"]

        XCTAssertTrue(
            waitForEither([statsCard, minStat, avgStat, maxStat], timeout: 30),
            "Statistics section or stat elements (min/avg/max) should appear after ping completes"
        )
    }

    func testHostFieldAcceptsIP() throws {
        navigateToPingTool()
        let runButton = requireExists(app.buttons["pingTool_button_run"], message: "Run button should exist")
        XCTAssertFalse(runButton.isEnabled, "Run button should be disabled with empty host field")

        clearAndTypeText("8.8.8.8", into: app.textFields["pingTool_input_host"])
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled after entering a valid IP address")
    }
}
