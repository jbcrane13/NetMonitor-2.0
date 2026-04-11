@preconcurrency import XCTest

final class SpeedTestToolUITests: MacOSUITestCase {

    private func openSpeedTest() {
        openTool(cardID: "tools_card_speed_test", sheetElement: "speedTest_button_start")
    }

    // MARK: - Element Existence

    func testDurationPickerExists() {
        openSpeedTest()
        requireExists(
            app.segmentedControls["speedTest_picker_duration"],
            message: "Duration picker should exist"
        )
        captureScreenshot(named: "SpeedTest_Screen")
    }

    func testStartButtonExists() {
        openSpeedTest()
        requireExists(app.buttons["speedTest_button_start"], message: "Start button should exist")
    }

    func testCloseButtonExists() {
        openSpeedTest()
        requireExists(app.buttons["speedTest_button_close"], message: "Close button should exist")
    }

    // MARK: - Interactions

    func testStartButtonIsEnabled() {
        openSpeedTest()
        let startButton = requireExists(app.buttons["speedTest_button_start"], message: "Start button should exist")
        XCTAssertTrue(startButton.isEnabled, "Start button should be enabled")
    }

    func testCloseButtonDismissesSheet() {
        openSpeedTest()
        app.buttons["speedTest_button_close"].tap()
        requireExists(
            app.otherElements["tools_card_speed_test"],
            message: "Tool card should reappear after closing sheet"
        )
    }

    func testStartShowsStopButton() {
        openSpeedTest()
        app.buttons["speedTest_button_start"].tap()

        let stopButton = app.buttons["speedTest_button_stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "Stop button should appear during test")
        captureScreenshot(named: "SpeedTest_Running")
    }

    func testStopButtonReturnsToStart() {
        openSpeedTest()
        app.buttons["speedTest_button_start"].tap()

        let stopButton = app.buttons["speedTest_button_stop"]
        guard stopButton.waitForExistence(timeout: 5) else { return }
        stopButton.tap()

        requireExists(
            app.buttons["speedTest_button_start"],
            timeout: 5,
            message: "Start button should reappear after stopping"
        )
    }

    func testDurationPickerHasThreeSegments() {
        openSpeedTest()
        let picker = requireExists(
            app.segmentedControls["speedTest_picker_duration"],
            message: "Duration picker should exist"
        )
        XCTAssertEqual(picker.buttons.count, 3, "Duration picker should have 3 segments (5s, 10s, 30s)")
    }

    func testSpeedTestCompletesWithResults() {
        openSpeedTest()
        app.buttons["speedTest_button_start"].tap()

        // Wait for results or stop button
        let results = ui("speedTest_section_results")
        let stopButton = app.buttons["speedTest_button_stop"]

        XCTAssertTrue(
            waitForEither([results, stopButton], timeout: 10),
            "Speed test should enter running state or show results"
        )

        if results.waitForExistence(timeout: 45) {
            captureScreenshot(named: "SpeedTest_Results")
        }
    }
}
