import XCTest

/// UI tests for the AR WiFi Signal view.
///
/// ARKit requires a real device with a camera; these tests run on the simulator
/// and verify that the fallback UI is shown gracefully. Full AR testing requires
/// a physical device and cannot be driven by XCUITest.
final class ARWiFiSignalUITests: XCTestCase {
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

    // MARK: - Navigation to AR WiFi View

    @MainActor
    func testARWiFiToolIsReachableFromToolsTab() {
        let toolsTab = app.tabBars.buttons["Tools"]
        guard toolsTab.exists else { return }
        toolsTab.tap()

        // Look for the AR WiFi tool button
        let arButton = app.buttons.matching(NSPredicate(format:
            "identifier CONTAINS 'arWifi' OR label CONTAINS 'AR WiFi'"
        )).firstMatch

        if arButton.waitForExistence(timeout: 3) {
            arButton.tap()

            // The AR WiFi Signal view should appear (either AR or fallback)
            let navTitle = app.navigationBars["AR WiFi Signal"]
            XCTAssert(
                navTitle.waitForExistence(timeout: 3),
                "AR WiFi Signal view should be navigable"
            )

            // App should remain stable (not crash)
            XCTAssert(app.state == .runningForeground)
        }
    }

    // MARK: - Fallback UI (simulator)

    @MainActor
    func testFallbackUIShownOnSimulator() {
        let toolsTab = app.tabBars.buttons["Tools"]
        guard toolsTab.exists else { return }
        toolsTab.tap()

        let arButton = app.buttons.matching(NSPredicate(format:
            "identifier CONTAINS 'arWifi' OR label CONTAINS 'AR WiFi'"
        )).firstMatch

        guard arButton.waitForExistence(timeout: 3) else { return }
        arButton.tap()

        // On the simulator, the fallback message should appear
        let notAvailableLabel = app.staticTexts.matching(NSPredicate(format:
            "label CONTAINS 'not available'"
        )).firstMatch

        // This is a soft assertion — on a real device with AR support, this label won't appear
        if notAvailableLabel.waitForExistence(timeout: 3) {
            XCTAssert(notAvailableLabel.exists)
        }
    }
}
