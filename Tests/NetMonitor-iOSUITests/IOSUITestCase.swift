import XCTest
@MainActor

class IOSUITestCase: XCTestCase {
    nonisolated(unsafe) nonisolated(unsafe) var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "System Alerts") { alert in
            let preferredButtons = [
                "Don’t Allow", "Don't Allow", "Not Now", "Cancel", "OK", "Allow While Using App", "Allow"
            ]

            for title in preferredButtons {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }

            let firstButton = alert.buttons.firstMatch
            if firstButton.exists {
                firstButton.tap()
                return true
            }
            return false
        }
        app.launchArguments += ["--uitesting", "--uitesting-reset"]
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["XCUITest"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch to foreground")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @discardableResult
    func requireExists(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        message: String
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        return element
    }

    @discardableResult
    func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    func clearAndTypeText(_ text: String, into element: XCUIElement) {
        requireExists(element, timeout: 5, message: "Expected text input before typing")
        element.tap()

        if let currentValue = element.value as? String,
           !currentValue.isEmpty,
           currentValue != element.placeholderValue {
            let deleteSequence = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            element.typeText(deleteSequence)
        }

        element.typeText(text)
    }

    func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 5) {
        if element.exists && element.isHittable {
            return
        }

        let scrollContainer: XCUIElement = {
            let table = app.tables.firstMatch
            if table.exists { return table }
            let collection = app.collectionViews.firstMatch
            if collection.exists { return collection }
            return app.scrollViews.firstMatch
        }()

        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return
            }
            if scrollContainer.exists {
                scrollContainer.swipeUp()
            } else {
                app.swipeUp()
            }
        }

        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return
            }
            if scrollContainer.exists {
                scrollContainer.swipeDown()
            } else {
                app.swipeDown()
            }
        }
    }

    func tapTrailingEdge(of element: XCUIElement) {
        requireExists(element, timeout: 5, message: "Expected element before tapping trailing edge")
        let coordinate = element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        coordinate.tap()
    }

    /// Captures a screenshot and attaches it to the test for visual review.
    func captureScreenshot(named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
}
