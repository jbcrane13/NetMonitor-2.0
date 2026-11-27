import XCTest

@MainActor
class NetMonitorMacOSUITests: MacOSUITestCase {

    func testAppLaunches() throws {
        XCTAssertTrue(app.windows.count > 0, "App should have at least one window")
    }
}
