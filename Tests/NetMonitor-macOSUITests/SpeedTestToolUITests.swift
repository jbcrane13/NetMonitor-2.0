import XCTest

@MainActor
final class SpeedTestToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools
        let sidebar = app.descendants(matching: .any)["sidebar_nav_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        // Open Speed Test tool
        let card = app.otherElements["tools_card_speed_test"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Element Existence

    func testDurationPickerExists() {
        XCTAssertTrue(app.segmentedControls["speedtest_picker_duration"].waitForExistence(timeout: 3))
    }

    func testStartButtonExists() {
        XCTAssertTrue(app.buttons["speedtest_button_start"].waitForExistence(timeout: 3))
    }

    func testCloseButtonExists() {
        XCTAssertTrue(app.buttons["speedtest_button_close"].waitForExistence(timeout: 3))
    }

    // MARK: - Interactions

    func testStartButtonIsEnabled() {
        let startButton = app.buttons["speedtest_button_start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 3))
        XCTAssertTrue(startButton.isEnabled)
    }

    func testCloseButtonDismissesSheet() {
        app.buttons["speedtest_button_close"].tap()
        XCTAssertTrue(app.otherElements["tools_card_speed_test"].waitForExistence(timeout: 3))
    }

    func testStartShowsStopButton() {
        let startButton = app.buttons["speedtest_button_start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 3))
        startButton.tap()

        // Stop button should appear
        let stopButton = app.buttons["speedtest_button_stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
    }

    func testStopButtonStopsTest() {
        app.buttons["speedtest_button_start"].tap()

        let stopButton = app.buttons["speedtest_button_stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
        stopButton.tap()

        // Start button should reappear
        XCTAssertTrue(app.buttons["speedtest_button_start"].waitForExistence(timeout: 5))
    }

    func testDurationPickerSegments() {
        let picker = app.segmentedControls["speedtest_picker_duration"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        // Should have 3 segments: 5s, 10s, 30s
        XCTAssertEqual(picker.buttons.count, 3)
    }
}
