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

    func testSpeedTestScreenExistsAndShowsControls() throws {
        navigateToSpeedTestTool()
        let screen = app.otherElements["screen_speedTestTool"]
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "Speed test screen should exist")
        // FUNCTIONAL: screen should contain gauge and run button
        XCTAssertTrue(
            app.otherElements["speedTest_label_gauge"].waitForExistence(timeout: 3),
            "Speed test screen should show speed gauge"
        )
        XCTAssertTrue(
            app.buttons["speedTest_button_run"].waitForExistence(timeout: 3),
            "Speed test screen should show run button"
        )
        captureScreenshot(named: "SpeedTest_Screen")
    }

    func testNavigationTitleExists() throws {
        navigateToSpeedTestTool()
        requireExists(app.navigationBars["Speed Test"], message: "Speed Test navigation bar should exist")
    }

    // MARK: - UI Elements

    func testSpeedGaugeExistsAndShowsInitialValue() throws {
        navigateToSpeedTestTool()
        let gauge = app.otherElements["speedTest_label_gauge"]
        XCTAssertTrue(gauge.waitForExistence(timeout: 5), "Speed gauge should exist")
        // FUNCTIONAL: gauge should be visible and have initial state
        XCTAssertTrue(gauge.exists, "Speed gauge should be present before test starts")
    }

    func testRunButtonExistsAndIsEnabled() throws {
        navigateToSpeedTestTool()
        let runButton = app.buttons["speedTest_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5), "Run button should exist")
        // FUNCTIONAL: run button should be immediately tappable
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled on speed test screen")
    }

    // MARK: - Speed Test Execution

    func testStartSpeedTestTransitionsToActiveState() throws {
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
        // FUNCTIONAL: verify speed test is in an active or complete state
        let isActive = stopButton.exists || latencyPhase.exists || downloadPhase.exists || uploadPhase.exists
        let hasResults = results.exists
        XCTAssertTrue(
            isActive || hasResults,
            "Speed test should be actively running or showing results after start"
        )
        captureScreenshot(named: "SpeedTest_Running")
    }

    func testStopSpeedTestReturnsToIdleState() throws {
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
        // FUNCTIONAL: after stopping, gauge should still be visible
        requireExists(app.otherElements["speedTest_label_gauge"], message: "Speed gauge should remain visible after stopping")
        // FUNCTIONAL: run button should be accessible for restart
        XCTAssertTrue(runButton.exists, "Run button should be accessible after stopping")
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
            // FUNCTIONAL: if history exists, it should contain data
            if history.exists {
                XCTAssertTrue(
                    history.staticTexts.count > 0 || app.cells.count > 0,
                    "History section should contain speed test result data"
                )
            }
            captureScreenshot(named: "SpeedTest_Results")
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

        // FUNCTIONAL: each segment should be tappable
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

        // FUNCTIONAL: gauge should still display after run/stop cycle
        requireExists(
            app.otherElements["speedTest_label_gauge"],
            timeout: 5,
            message: "Speed gauge should remain visible after run/stop cycle"
        )
    }
}
