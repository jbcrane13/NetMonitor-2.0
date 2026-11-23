import XCTest

/// Shared base class for deterministic macOS UI tests.
///
/// Mirrors the iOS ``IOSUITestCase`` pattern: launches with `--uitesting`
/// flags so the app enters a lightweight test mode (monitoring disabled,
/// auto-start off), and provides common helpers used across outcome and
/// interaction-flow tests.
///
/// macOS 27 treats a synthesized `tap()` as a no-op, so every helper and test
/// in this target uses `click()` (#352).
@MainActor
class MacOSUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["XCUITest"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "App main window should appear after launch")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Helpers

    /// Assert an element exists within a timeout and return it.
    @discardableResult
    func requireExists(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        message: String
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        return element
    }

    /// Wait for an element to disappear.
    @discardableResult
    func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Clear an existing text field and type new text.
    func clearAndTypeText(_ text: String, into element: XCUIElement) {
        requireExists(element, timeout: 5, message: "Expected text input before typing")
        element.click()

        if let currentValue = element.value as? String,
           !currentValue.isEmpty,
           currentValue != element.placeholderValue {
            element.click()
            element.typeKey("a", modifierFlags: .command)
            element.typeText(text)
        } else {
            element.typeText(text)
        }
    }

    /// Captures a screenshot and attaches it to the test for visual review.
    func captureScreenshot(named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Poll until at least one of the given elements exists.
    func waitForEither(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    /// Shorthand for finding any descendant by accessibility identifier.
    func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    // MARK: - Navigation

    /// Click a sidebar item and wait for its detail pane.
    func navigateToSidebar(_ section: String) {
        // The row's id is stamped onto its icon and label on macOS 27, so match the first.
        let sidebarItem = ui("sidebar_nav_\(section)").firstMatch
        requireExists(sidebarItem, timeout: 5,
                      message: "Sidebar item sidebar_nav_\(section) should exist")
        sidebarItem.click()
        requireExists(ui("contentView_nav_\(section)").firstMatch, timeout: 5,
                      message: "Detail pane contentView_nav_\(section) should appear after selecting sidebar_\(section)")
    }

    /// Navigate to the Tools detail pane, click a tool card, and verify the tool
    /// sheet opens by checking for a known element inside the sheet.
    func openTool(cardID: String, sheetElement: String) {
        navigateToSidebar("tools")
        let card = ui(cardID).firstMatch
        requireExists(card, timeout: 5, message: "Tool card \(cardID) should exist")
        card.click()
        requireExists(ui(sheetElement), timeout: 5,
                      message: "Sheet element \(sheetElement) should appear after opening \(cardID)")
    }

    /// Close the currently open tool sheet via its close button and verify the
    /// tool card grid reappears.
    func closeTool(closeButtonID: String, cardID: String) {
        let closeButton = app.buttons[closeButtonID]
        requireExists(closeButton, message: "Close button \(closeButtonID) should exist")
        closeButton.click()
        XCTAssertTrue(waitForDisappearance(closeButton), "Sheet should close")
        requireExists(ui(cardID).firstMatch, timeout: 5,
                      message: "Tool card \(cardID) should reappear after closing sheet")
    }
}
