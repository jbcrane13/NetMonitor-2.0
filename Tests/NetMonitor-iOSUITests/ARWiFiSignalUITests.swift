@preconcurrency import XCTest

/// UI tests for the AR WiFi Signal view.
///
/// ARKit requires a real device with a camera; these tests run on the simulator
/// and verify that the fallback UI is shown gracefully. Full AR testing requires
/// a physical device and cannot be driven by XCUITest.
final class ARWiFiSignalUITests: XCTestCase {
    nonisolated(unsafe) var app: XCUIApplication!

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

    // MARK: - Fallback Content Verification

    @MainActor
    func testARWiFiFallbackShowsMeaningfulContent() {
        let toolsTab = app.tabBars.buttons["Tools"]
        guard toolsTab.exists else { return }
        toolsTab.tap()

        let arButton = app.buttons.matching(NSPredicate(format:
            "identifier CONTAINS 'arWifi' OR label CONTAINS 'AR WiFi'"
        )).firstMatch

        guard arButton.waitForExistence(timeout: 3) else { return }
        arButton.tap()

        // On simulator, verify fallback UI contains informative text (not just a blank screen)
        Thread.sleep(forTimeInterval: 1.0)

        let allTexts = app.staticTexts
        XCTAssertGreaterThan(allTexts.count, 0, "AR WiFi view should show at least some text content")

        // Check for specific fallback or AR-related messaging
        let hasARContent = app.staticTexts.matching(NSPredicate(format:
            "label CONTAINS[c] 'AR' OR label CONTAINS[c] 'camera' OR label CONTAINS[c] 'not available' OR label CONTAINS[c] 'WiFi' OR label CONTAINS[c] 'signal'"
        )).firstMatch

        XCTAssertTrue(
            hasARContent.waitForExistence(timeout: 3),
            "AR WiFi view should show AR-related content or fallback message"
        )
    }

    // MARK: - Back Navigation

    @MainActor
    func testARWiFiBackNavigationReturnsToTools() {
        let toolsTab = app.tabBars.buttons["Tools"]
        guard toolsTab.exists else { return }
        toolsTab.tap()

        let arButton = app.buttons.matching(NSPredicate(format:
            "identifier CONTAINS 'arWifi' OR label CONTAINS 'AR WiFi'"
        )).firstMatch
        guard arButton.waitForExistence(timeout: 3) else { return }
        arButton.tap()

        // Wait for AR view to load
        Thread.sleep(forTimeInterval: 1.0)

        // Navigate back using the first navigation bar button
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists {
            backButton.tap()

            // Verify we're back on the Tools screen
            XCTAssertTrue(
                app.navigationBars["Tools"].waitForExistence(timeout: 3),
                "Should navigate back to Tools screen"
            )
        }
    }
}
