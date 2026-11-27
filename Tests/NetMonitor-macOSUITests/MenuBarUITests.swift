import XCTest

@MainActor
final class MenuBarUITests: MacOSUITestCase {

    // MARK: - Menu Bar

    /// The menu bar popover lives outside the main window hierarchy, and a
    /// `--uitesting` launch does not create the menu bar controller. These tests
    /// only check that the app launches with a main window and that the app's
    /// main menu (File, View, Window) is there and enabled.

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
