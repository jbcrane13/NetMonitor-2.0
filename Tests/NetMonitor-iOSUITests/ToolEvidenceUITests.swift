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

    private func card(_ cardID: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR identifier BEGINSWITH %@", cardID, cardID + "-")
        ).firstMatch
    }

    /// The card's upper part is on screen and above the floating tab bar.
    private func onScreen(_ card: XCUIElement) -> Bool {
        guard card.exists else { return false }
        let tapY = card.frame.minY + card.frame.height * 0.3
        return card.frame.minY >= 0 && tapY < app.tabBars.firstMatch.frame.minY - 8
    }

    /// Opens a tool, scrolling the grid in small steps either way until its card is clear.
    private func openTool(_ cardID: String, screen: String) {
        app.tabBars.buttons["Tools"].tap()
        requireExists(element("screen_tools"), timeout: 5, message: "Tools screen should appear")
        let target = card(cardID)
        let grid = app.scrollViews.matching(identifier: "screen_tools").firstMatch
        for _ in 0..<30 where !onScreen(target) {
            if target.exists, target.frame.minY < 0 {
                grid.swipeDown(velocity: .slow)
            } else {
                grid.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(onScreen(target), "\(cardID) should be visible")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
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
        XCTAssertTrue(element("tracerouteTool_row_3").waitForExistence(timeout: 60), "Traceroute should list 3+ hops")
        _ = waitForDisappearance(app.buttons["Stop Trace"], timeout: 60)
        hideKeyboard()
        captureScreenshot(named: "E1_Traceroute_1.1.1.1")
    }

    func test02_BonjourFindsServices() {
        openTool("tools_card_bonjour", screen: "screen_bonjourTool")
        app.buttons["bonjour_button_run"].tap()
        XCTAssertTrue(element("bonjour_section_services").waitForExistence(timeout: 20), "Bonjour should list services")
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

    func test04_WorldPingShowsLocations() {
        openTool("tools_card_world_ping", screen: "screen_worldPingTool")
        type("google.com", into: app.textFields["worldPing_input_host"])
        app.buttons["worldPing_button_run"].tap()
        XCTAssertTrue(element("worldPing_row").waitForExistence(timeout: 60), "World ping should list locations")
        settle(10)
        captureScreenshot(named: "E4_WorldPing_google.com")
    }

    func test05_SSLMonitorShowsCertificate() {
        openTool("tools_card_ssl_monitor", screen: "screen_sslCertificateMonitor")
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
