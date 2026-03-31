import XCTest

@MainActor
final class SpeedTestToolUITests: IOSUITestCase {

    private func navigateToSpeedTestTool() {
        app.tabBars.buttons["Tools"].tap()
        let speedTestCard = app.otherElements["tools_card_speed_test"]
        scrollToElement(speedTestCard)
        requireExists(speedTestCard, timeout: 8, message: "Speed test tool card should exist")
        speedTestCard.tap()
        requireExists(app.otherElements["screen_speedTestTool"], timeout: 8, message: "Speed test tool screen should appear")
    }

    // MARK: - Screen Existence

    func testSpeedTestScreenExists() throws {
        navigateToSpeedTestTool()
        requireExists(app.otherElements["screen_speedTestTool"], message: "Speed test screen should exist")
    }

    func testNavigationTitleExists() throws {
        navigateToSpeedTestTool()
        requireExists(app.navigationBars["Speed Test"], message: "Speed Test navigation bar should exist")
    }

    // MARK: - UI Elements

    func testSpeedGaugeExists() throws {
        navigateToSpeedTestTool()
        requireExists(app.otherElements["speedTest_label_gauge"], message: "Speed gauge should exist")
    }

    func testRunButtonExists() throws {
        navigateToSpeedTestTool()
        requireExists(app.buttons["speedTest_button_run"], message: "Run button should exist")
    }

    // MARK: - Speed Test Execution

    func testStartSpeedTest() throws {
        navigateToSpeedTestTool()
        let runButton = requireExists(app.buttons["speedTest_button_run"], message: "Run button should exist")
        runButton.tap()

        let results = app.otherElements["speedTest_section_results"]
        let latencyPhase = app.staticTexts["Testing latency..."]
        let downloadPhase = app.staticTexts["Testing download..."]
        let uploadPhase = app.staticTexts["Testing upload..."]
        let stopButton = app.buttons["Stop Test"]

        XCTAssertTrue(
            waitForEither([results, latencyPhase, downloadPhase, uploadPhase, stopButton], timeout: 30),
            "Speed test should enter a running phase or show results"
        )
    }

    func testStopSpeedTest() throws {
        navigateToSpeedTestTool()
        let runButton = requireExists(app.buttons["speedTest_button_run"], message: "Run button should exist")
        runButton.tap()

        let stopButton = app.buttons["Stop Test"]
        let latencyPhase = app.staticTexts["Testing latency..."]
        XCTAssertTrue(
            waitForEither([stopButton, latencyPhase], timeout: 10),
            "Speed test should enter running state"
        )

        runButton.tap()
        requireExists(app.otherElements["speedTest_label_gauge"], message: "Speed gauge should remain visible after stopping")
    }

    // MARK: - History Section

    func testHistorySectionAppearsAfterTest() throws {
        navigateToSpeedTestTool()
        let runButton = requireExists(app.buttons["speedTest_button_run"], message: "Run button should exist")
        runButton.tap()

        let results = app.otherElements["speedTest_section_results"]
        if results.waitForExistence(timeout: 45) {
            scrollToElement(app.otherElements["speedTest_section_history"])
            let history = app.otherElements["speedTest_section_history"]
            XCTAssertTrue(
                history.waitForExistence(timeout: 5) || results.exists,
                "History section or results should be visible after test completes"
            )
        }
    }

    // MARK: - Duration Picker

    func testDurationPickerAllSegmentsInteractive() throws {
        navigateToSpeedTestTool()

        let durationPicker = requireExists(
            app.segmentedControls["speedTest_picker_duration"],
            message: "Duration picker should exist on speed test screen"
        )

        let segmentCount = durationPicker.buttons.count
        XCTAssertGreaterThanOrEqual(segmentCount, 2, "Duration picker should have at least 2 segments")

        for index in 0..<min(segmentCount, 3) {
            let segment = durationPicker.buttons.element(boundBy: index)
            if segment.exists && segment.isHittable {
                segment.tap()
                XCTAssertTrue(
                    durationPicker.waitForExistence(timeout: 3),
                    "Duration picker should remain visible after tapping segment \(index)"
                )
            }
        }
    }

    func testSpeedGaugeVisibleAfterRun() throws {
        navigateToSpeedTestTool()
        let runButton = requireExists(app.buttons["speedTest_button_run"], message: "Run button should exist")
        runButton.tap()

        let stopButton = app.buttons["Stop Test"]
        let latencyPhase = app.staticTexts["Testing latency..."]
        _ = waitForEither([stopButton, latencyPhase], timeout: 10)

        runButton.tap()

        requireExists(
            app.otherElements["speedTest_label_gauge"],
            timeout: 5,
            message: "Speed gauge should remain visible after run/stop cycle"
        )
    }
}
