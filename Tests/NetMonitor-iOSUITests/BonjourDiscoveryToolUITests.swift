import XCTest

final class BonjourDiscoveryToolUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Tools"].tap()
        let bonjourCard = app.otherElements["tools_card_bonjour"]
        if bonjourCard.waitForExistence(timeout: 5) {
            bonjourCard.tap()
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testBonjourScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_bonjourTool"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Bonjour Discovery"].waitForExistence(timeout: 5))
    }

    // MARK: - UI Elements

    func testRunButtonExists() throws {
        XCTAssertTrue(app.buttons["bonjour_button_run"].waitForExistence(timeout: 5))
    }

    // MARK: - Discovery Execution

    func testStartDiscovery() throws {
        let runButton = app.buttons["bonjour_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        runButton.tap()

        // Either services appear or empty state shows after discovery
        sleep(5)
        let services = app.otherElements["bonjour_section_services"]
        let emptyState = app.otherElements["bonjour_emptystate_noservices"]
        // One of these should be visible, or still discovering
        XCTAssertTrue(services.exists || emptyState.exists || app.activityIndicators.firstMatch.exists)
    }

    func testStopDiscovery() throws {
        let runButton = app.buttons["bonjour_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        runButton.tap()

        sleep(2)
        // Tap again to stop
        runButton.tap()

        // Screen should still be present
        XCTAssertTrue(app.otherElements["screen_bonjourTool"].exists)
    }

    func testClearResultsButton() throws {
        let runButton = app.buttons["bonjour_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        runButton.tap()

        sleep(5)
        // Stop discovery
        runButton.tap()
        sleep(1)

        let clearButton = app.buttons["bonjour_button_clear"]
        if clearButton.waitForExistence(timeout: 3) {
            clearButton.tap()
            XCTAssertFalse(app.otherElements["bonjour_section_services"].exists)
        }
    }

    // MARK: - Empty State

    func testEmptyStateAfterNoResults() throws {
        let runButton = app.buttons["bonjour_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        runButton.tap()

        // Wait for discovery to complete
        sleep(8)
        runButton.tap()
        sleep(1)

        // Either services or empty state should show
        let services = app.otherElements["bonjour_section_services"]
        let emptyState = app.otherElements["bonjour_emptystate_noservices"]
        XCTAssertTrue(services.exists || emptyState.exists)
    }
}
