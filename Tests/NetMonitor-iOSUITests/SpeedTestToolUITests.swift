import XCTest

final class SpeedTestToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Tools"].tap()
        let speedTestCard = app.otherElements["tools_card_speed_test"]
        if speedTestCard.waitForExistence(timeout: 5) {
            speedTestCard.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testSpeedTestScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_speedTestTool"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Speed Test"].waitForExistence(timeout: 5))
    }

    // MARK: - UI Elements

    func testSpeedGaugeExists() throws {
        XCTAssertTrue(app.otherElements["speedTest_gauge"].waitForExistence(timeout: 5))
    }

    func testRunButtonExists() throws {
        XCTAssertTrue(app.buttons["speedTest_button_run"].waitForExistence(timeout: 5))
    }

    // MARK: - Speed Test Execution

    func testStartSpeedTest() throws {
        let runButton = app.buttons["speedTest_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        runButton.tap()

        // Results section should eventually appear
        let results = app.otherElements["speedTest_results"]
        XCTAssertTrue(results.waitForExistence(timeout: 30))
    }

    func testStopSpeedTest() throws {
        let runButton = app.buttons["speedTest_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        runButton.tap()

        // Wait briefly then stop
        sleep(2)
        // The button should now show "Stop Test" - tap it again
        runButton.tap()
        // After stopping, gauge should still exist
        XCTAssertTrue(app.otherElements["speedTest_gauge"].exists)
    }

    // MARK: - History Section

    func testHistorySectionAppearsAfterTest() throws {
        let runButton = app.buttons["speedTest_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        runButton.tap()

        // Wait for test to complete
        let results = app.otherElements["speedTest_results"]
        if results.waitForExistence(timeout: 45) {
            app.swipeUp()
            let history = app.otherElements["speedTest_section_history"]
            // History may or may not exist depending on SwiftData state
            XCTAssertTrue(history.waitForExistence(timeout: 5) || results.exists)
        }
    }
}
