import XCTest

@MainActor
class IOSUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// Extra launch-environment entries applied before `app.launch()`.
    /// Override in a subclass that needs a special app configuration for
    /// one test file (e.g. a deterministic device fixture) instead of
    /// duplicating this class's `setUp()`.
    var additionalLaunchEnvironment: [String: String] { [:] }

    /// Extra launch arguments, after `--uitesting --uitesting-reset`.
    var additionalLaunchArguments: [String] { [] }

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "System Alerts") { alert in
            let preferredButtons = [
                "Don't Allow", "Don't Allow", "Not Now", "Cancel", "OK", "Allow While Using App", "Allow"
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
        app.launchArguments += ["--uitesting", "--uitesting-reset"] + additionalLaunchArguments
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["XCUITest"] = "1"
        for (key, value) in additionalLaunchEnvironment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch to foreground")
    }

    override func tearDown() async throws {
        try await super.tearDown()
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
            if table.exists {
                return table
            }
            let collection = app.collectionViews.firstMatch
            if collection.exists {
                return collection
            }
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

extension XCUIElement {
    /// Flips a `Toggle`. On iOS 26+ the identified `Switch` is the full-width row, so a tap at its centre
    /// lands on the label and changes nothing; the unnamed `Switch` inside it is the control. Waits for
    /// the value to change and fails the test if it doesn't.
    func flipSwitch(file: StaticString = #filePath, line: UInt = #line) {
        let before = value as? String
        let control = switches.firstMatch
        if control.exists {
            control.tap()
        } else {
            coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let changed = NSPredicate(format: "value != %@", before ?? "")
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: changed, object: self)], timeout: 3)
        XCTAssertEqual(result, .completed, "\(self) should change value after the tap", file: file, line: line)
    }
}

extension XCUIApplication {
    /// Some element that carries the accessibility ID, of any type: first match. The iOS 27 runtime
    /// reports a screen as a `CollectionView`, `ScrollView` or `Other` depending on its content, so an
    /// `otherElements["screen_…"]` lookup misses it (#604); and it stamps a container's ID onto
    /// children without their own, so a plain `[id]` subscript finds several and fails (#610).
    /// Use it to ask whether a screen, card or control is there, or to tap it. The match can be a
    /// stamped child rather than the container, so don't read a container's `staticTexts` or frame
    /// from it: use `texts(carrying:)` for a card's content, or an element-type query.
    func byID(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The non-empty static texts inside the container with this ID. iOS 27 stamps the container's ID
    /// onto them, so this finds a card's real content whichever element `byID` returned.
    func texts(carrying identifier: String) -> XCUIElementQuery {
        staticTexts.matching(identifier: identifier).matching(NSPredicate(format: "label != ''"))
    }

    /// The first text inside the container whose label matches the regular expression, or a
    /// non-existent element.
    func text(carrying identifier: String, matching pattern: String) -> XCUIElement {
        texts(carrying: identifier).matching(NSPredicate(format: "label MATCHES %@", pattern)).firstMatch
    }
}

extension XCUIElementQuery {
    /// True when nothing matches. `count == 0` is rejected by SwiftLint's `empty_count` rule, and
    /// `isEmpty` is not a member of `XCUIElementQuery`, so a stock name could clash with a later SDK.
    var hasNoMatches: Bool { !element(boundBy: 0).exists }
}
