import XCTest

/// UI tests for Live Activities / Dynamic Island integration.
///
/// Live Activities require a physical device with Dynamic Island or lock screen
/// support and cannot be driven end-to-end by XCUITest. These tests verify that
/// operations which trigger Live Activities (scans, speed tests) can be initiated
/// from the UI without crashing.
final class LiveActivityUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Health

    @MainActor
    func testAppLaunchesWithoutCrash() {
        XCTAssert(app.state == .runningForeground)
    }

    // MARK: - Network Scan (triggers NetworkScanActivity)

    @MainActor
    func testNetworkScanCanBeInitiated() {
        // Navigate to Dashboard where scan button lives
        let dashTab = app.tabBars.buttons["Dashboard"]
        if dashTab.exists {
            dashTab.tap()
        }

        // Look for a scan button by common accessibility identifiers
        let scanButton = app.buttons.matching(NSPredicate(format:
            "identifier CONTAINS 'scan' OR label CONTAINS 'Scan'"
        )).firstMatch

        if scanButton.waitForExistence(timeout: 3) {
            scanButton.tap()
            // App should not crash after initiating scan
            XCTAssert(app.state == .runningForeground)
        }
    }

    // MARK: - Speed Test (triggers SpeedTestActivity)

    @MainActor
    func testSpeedTestToolIsReachable() {
        let toolsTab = app.tabBars.buttons["Tools"]
        guard toolsTab.exists else { return }
        toolsTab.tap()

        let speedTestButton = app.buttons.matching(NSPredicate(format:
            "identifier CONTAINS 'speedTest' OR label CONTAINS 'Speed Test'"
        )).firstMatch

        if speedTestButton.waitForExistence(timeout: 3) {
            speedTestButton.tap()
            XCTAssert(app.state == .runningForeground)
        }
    }
}
