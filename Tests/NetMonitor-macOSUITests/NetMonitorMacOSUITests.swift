import XCTest

@MainActor
class NetMonitorMacOSUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    func testAppLaunches() throws {
        XCTAssertTrue(app.windows.count > 0, "App should have at least one window")
    }
}
