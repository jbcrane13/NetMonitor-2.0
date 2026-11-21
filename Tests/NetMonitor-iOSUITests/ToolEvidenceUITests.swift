import XCTest

/// Release evidence for tools whose `FunctionalSmokeTests` screenshot can be taken before the
/// result arrives (a trace still running, a speed test mid-download) or whose card the smoke
/// suite's scroll can step past. Each test waits for the finished result, hides the keyboard,
/// then captures a screenshot.
@MainActor
final class ToolEvidenceUITests: IOSUITestCase {

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The card's button, else any element carrying its identifier (some cards expose it only on
    /// their contents); a coordinate tap opens the card either way.
    private func card(_ cardID: String) -> XCUIElement {
        let button = app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR identifier BEGINSWITH %@", cardID, cardID + "-")
        ).firstMatch
        if button.exists {
            return button
        }
        let byID = element(cardID)
        if byID.exists {
            return byID
        }
        // The card's title text, e.g. "Speed Test" for tools_card_speed_test.
        return app.staticTexts[Self.titles[cardID] ?? cardID].firstMatch
    }

    private static let titles = [
        "tools_card_speed_test": "Speed Test",
        "tools_card_world_ping": "World Ping",
        "tools_card_ssl_monitor": "SSL Monitor"
    ]

    /// The card's upper part is on screen and above the floating tab bar.
    private func onScreen(_ card: XCUIElement) -> Bool {
        guard card.exists else { return false }
        let tapY = card.frame.minY + card.frame.height * 0.3
        return card.frame.minY >= 0 && tapY < app.tabBars.firstMatch.frame.minY - 8
    }

    /// Opens a tool. The grid is lazy, so a card exists only while on screen, and a swipe (even a
    /// slow one, on iOS 26) can carry it past between checks. Short drags in the left gutter, which
    /// never land on a card, move the grid a fixed 15% of its height per step instead.
    private func openTool(_ cardID: String, screen: String) {
        openToolCardOnly(cardID)
        card(cardID).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        requireExists(element(screen), timeout: 8, message: "\(screen) should appear")
    }

    /// Scrolls the Tools grid until the card is clear, without opening it.
    private func openToolCardOnly(_ cardID: String) {
        app.tabBars.buttons["Tools"].tap()
        requireExists(element("screen_tools"), timeout: 5, message: "Tools screen should appear")
        let grid = app.scrollViews.matching(identifier: "screen_tools").firstMatch
        var target = card(cardID)
        var reachedEnd = false
        for attempt in 0..<40 where !onScreen(target) {
            // Mid-grid cards can be skipped on the way down; from the last card, scan back up.
            reachedEnd = reachedEnd || element("tools_card_web_browser").exists
            let back = reachedEnd || (target.exists && target.frame.minY < 0)
            let from = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: back ? 0.4 : 0.6))
            let to = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: back ? 0.55 : 0.45))
            from.press(forDuration: 0.01, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
            target = card(cardID)
            if attempt == 39 {
                captureScreenshot(named: "nav_fail_\(cardID)")
                let seen = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier CONTAINS 'tools_card'")).allElementsBoundByIndex
                    .map { "\($0.identifier) \($0.elementType.rawValue) \($0.frame)" }
                let note = XCTAttachment(string: seen.joined(separator: "\n"))
                note.name = "nav_ids_\(cardID)"
                note.lifetime = .keepAlways
                add(note)
            }
        }
        XCTAssertTrue(onScreen(target), "\(cardID) should be visible")
    }

    /// Opens a card by its description text, which only the grid card shows ("Speed Test" is also
    /// a Quick Action button). Drags in the gutter until the text is clear of the tab bar, scanning
    /// back up once the last card is reached.
    private func openByDescription(_ description: String, screen: String) {
        app.tabBars.buttons["Tools"].tap()
        requireExists(element("screen_tools"), timeout: 5, message: "Tools screen should appear")
        let grid = app.scrollViews.matching(identifier: "screen_tools").firstMatch
        let text = app.staticTexts.matching(NSPredicate(format: "label == %@", description)).firstMatch
        var reachedEnd = false
        for _ in 0..<40 where !onScreen(text) {
            reachedEnd = reachedEnd || element("tools_card_web_browser").exists
            let back = reachedEnd || (text.exists && text.frame.minY < 0)
            let from = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: back ? 0.4 : 0.6))
            let to = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: back ? 0.55 : 0.45))
            from.press(forDuration: 0.01, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(onScreen(text), "\(description) should be visible")
        text.tap()
        requireExists(element(screen), timeout: 8, message: "\(screen) should appear")
    }

    private func type(_ text: String, into field: XCUIElement) {
        clearAndTypeText(text, into: field)
        hideKeyboard()
    }

    private func hideKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        if app.keyboards.buttons["Done"].exists {
            app.keyboards.buttons["Done"].tap()
        } else {
            app.navigationBars.firstMatch.tap()
        }
    }

    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func test01_TracerouteFinishes() {
        openTool("tools_card_traceroute", screen: "screen_tracerouteTool")
        type("1.1.1.1", into: app.textFields["tracerouteTool_input_host"])
        app.buttons["tracerouteTool_button_run"].tap()
        // Hop rows carry the section's identifier; the header counts them ("8 hops").
        let hopCount = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[3-9] hops|[1-9][0-9] hops")).firstMatch
        XCTAssertTrue(hopCount.waitForExistence(timeout: 60), "Traceroute should list 3+ hops")
        _ = waitForDisappearance(app.buttons["Stop Trace"], timeout: 60)
        hideKeyboard()
        captureScreenshot(named: "E1_Traceroute_1.1.1.1")
    }

    func test02_BonjourFindsServices() {
        openTool("tools_card_bonjour", screen: "screen_bonjourTool")
        app.buttons["bonjour_button_run"].tap()
        // The simulator only sees LAN services once macOS grants it local network access.
        XCTAssertTrue(
            waitForEither([element("bonjour_section_services"), element("bonjour_label_noServices")], timeout: 20),
            "Bonjour should finish discovery"
        )
        settle(3)
        captureScreenshot(named: "E2_Bonjour_services")
    }

    func test03_SpeedTestCompletes() {
        openTool("tools_card_speed_test", screen: "screen_speedTestTool")
        app.buttons["speedTest_button_run"].tap()
        XCTAssertTrue(app.buttons["Stop Test"].waitForExistence(timeout: 8), "Speed test should start")
        XCTAssertTrue(waitForDisappearance(app.buttons["Stop Test"], timeout: 90), "Speed test should finish")
        settle(1)
        captureScreenshot(named: "E3_SpeedTest_complete")
    }

    func test04_WorldPingShowsLocations() throws {
        // XCUITest doesn't report the Monitoring row's cards in the lazy Tools grid (#469).
        throw XCTSkip("Tools grid card unreachable from XCUITest (#469)")
        openByDescription("Global latency check", screen: "screen_worldPingTool")
        type("google.com", into: app.textFields["worldPing_input_host"])
        app.buttons["worldPing_button_run"].tap()
        XCTAssertTrue(element("worldPing_row").waitForExistence(timeout: 60), "World ping should list locations")
        settle(10)
        captureScreenshot(named: "E4_WorldPing_google.com")
    }

    func test05_SSLMonitorShowsCertificate() throws {
        // XCUITest doesn't report the Monitoring row's cards in the lazy Tools grid (#469).
        throw XCTSkip("Tools grid card unreachable from XCUITest (#469)")
        openByDescription("Certificate expiry check", screen: "screen_sslCertificateMonitor")
        type("apple.com", into: app.textFields["ssl_monitor_input_domain"])
        app.buttons["sslMonitor_button_query"].tap()
        XCTAssertTrue(
            waitForEither([element("sslMonitor_card_ssl"), element("sslMonitor_label_error")], timeout: 30),
            "SSL monitor should show the certificate"
        )
        settle(2)
        captureScreenshot(named: "E5_SSLMonitor_apple.com")
    }

    func test06_GeoTraceShowsHops() {
        openTool("tools_card_geo_trace", screen: "screen_geoTrace")
        let field = app.textFields.matching(
            NSPredicate(format: "identifier == 'geoTrace_input_host' OR placeholderValue == 'Hostname or IP address'")
        ).firstMatch
        type("8.8.8.8", into: field)
        app.buttons.matching(NSPredicate(format: "identifier == 'geoTrace_button_trace' OR label == 'Trace'")).firstMatch.tap()
        let hops = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*[1-9][0-9]* hops?.*")).firstMatch
        XCTAssertTrue(hops.waitForExistence(timeout: 60), "Geo trace should report hops")
        _ = waitForDisappearance(app.buttons.matching(NSPredicate(format: "label == 'Stop'")).firstMatch, timeout: 60)
        settle(3)
        captureScreenshot(named: "E6_GeoTrace_8.8.8.8")
    }
}
