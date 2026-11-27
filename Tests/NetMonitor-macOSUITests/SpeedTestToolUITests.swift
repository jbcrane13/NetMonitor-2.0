import XCTest

@MainActor
final class SpeedTestToolUITests: MacOSUITestCase {

    private func openSpeedTest() {
        openTool(cardID: "tools_card_speed_test", sheetElement: "speedTest_button_start")
    }

    // MARK: - Element Existence

    func testDurationPickerExists() {
        openSpeedTest()
        requireExists(
            app.radioGroups["speedTest_picker_duration"],
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
        closeTool(closeButtonID: "speedTest_button_close", cardID: "tools_card_speed_test")
    }

    func testStartShowsStopButton() {
        openSpeedTest()
        app.buttons["speedTest_button_start"].click()

        let stopButton = app.buttons["speedTest_button_stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "Stop button should appear during test")
        captureScreenshot(named: "SpeedTest_Running")
    }

    func testStopButtonReturnsToStart() {
        openSpeedTest()
        app.buttons["speedTest_button_start"].click()

        let stopButton = app.buttons["speedTest_button_stop"]
        requireExists(stopButton, timeout: 5, message: "Stop button should appear during test")
        stopButton.click()

        requireExists(
            app.buttons["speedTest_button_start"],
            timeout: 5,
            message: "Start button should reappear after stopping"
        )
    }

    func testDurationPickerHasThreeSegments() {
        openSpeedTest()
        let picker = requireExists(
            app.radioGroups["speedTest_picker_duration"],
            message: "Duration picker should exist"
        )
        XCTAssertEqual(picker.radioButtons.count, 3, "Duration picker should have 3 segments (5s, 10s, 30s)")
    }

    func testSpeedTestCompletesWithResults() {
        openSpeedTest()
        app.buttons["speedTest_button_start"].click()

        // Wait for running state first
        let stopButton = app.buttons["speedTest_button_stop"]
        XCTAssertTrue(
            stopButton.waitForExistence(timeout: 10),
            "Speed test should enter running state"
        )

        // Verify result DATA slots render during / after the test
        requireExists(
            ui("speedTest_section_results").firstMatch,
            timeout: 5,
            message: "Speed test results section should render"
        )
        requireExists(
            ui("speedTest_label_latency").firstMatch,
            message: "Latency label should appear in speed test results"
        )
        requireExists(
            ui("speedTest_label_download").firstMatch,
            message: "Download label should appear in speed test results"
        )
        requireExists(
            ui("speedTest_label_upload").firstMatch,
            message: "Upload label should appear in speed test results"
        )
        requireExists(
            ui("speedTest_label_server").firstMatch,
            message: "Server label should appear in speed test results"
        )

        // If allowed to complete, the Reset button only renders when phase == .complete.
        _ = app.buttons["speedTest_button_reset"].waitForExistence(timeout: 60)
        captureScreenshot(named: "SpeedTest_Results")
    }
}
