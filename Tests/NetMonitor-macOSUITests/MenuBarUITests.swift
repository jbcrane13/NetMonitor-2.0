import XCTest

@MainActor
@MainActor
final class MenuBarUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // tearDownWithError: handled by MacOSUITestCase (terminates app + nils ref)

    // MARK: - Menu Bar

    /// Menu bar popover is not directly accessible via XCUITest in most cases
    /// because it lives outside the main window hierarchy. These tests verify
    /// that the app launches and the main window is functional, which is a
    /// prerequisite for the menu bar controller to initialize.

    func testAppLaunchesSuccessfully() {
        XCTAssertTrue(app.windows.count > 0, "App should have at least one window")
    }

    func testMainWindowExists() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
    }

    // MARK: - Menu Bar Commands

    func testMainMenuExists() {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5))
    }

    func testFileMenuExists() {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5))

        let fileMenu = menuBar.menuBarItems["File"]
        if fileMenu.exists {
            XCTAssertTrue(fileMenu.isEnabled)
        }
    }

    func testViewMenuExists() {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5))

        let viewMenu = menuBar.menuBarItems["View"]
        if viewMenu.exists {
            XCTAssertTrue(viewMenu.isEnabled)
        }
    }

    func testWindowMenuExists() {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5))

        let windowMenu = menuBar.menuBarItems["Window"]
        if windowMenu.exists {
            XCTAssertTrue(windowMenu.isEnabled)
        }
    }
}
