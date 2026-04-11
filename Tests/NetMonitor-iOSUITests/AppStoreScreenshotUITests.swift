@preconcurrency import XCTest

final class AppStoreScreenshotUITests: IOSUITestCase {
    private lazy var outputDirectory: URL = {
        let env = ProcessInfo.processInfo.environment
        let path = env["APPSTORE_SCREENSHOT_DIR"] ?? "/tmp/netmonitor-appstore-screenshots"
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    func testCaptureAppStoreScreenshots() throws {
        try prepareOutputDirectory()

        // 1) Dashboard
        XCTAssertTrue(ui("screen_dashboard").waitForExistence(timeout: 10))
        capture("01-dashboard")

        // 2) Network Map
        openTab("Map", expectedScreen: "screen_networkMap")
        capture("02-network-map")

        // 3) Tools Hub
        openTab("Tools", expectedScreen: "screen_tools")
        capture("03-tools")

        // 4) Geo Trace
        captureToolScreen(
            toolCardIdentifier: "tools_card_geo_trace",
            expectedScreenIdentifier: "screen_geoTrace",
            fileName: "04-geo-trace"
        )

        // 5) Speed Test
        captureToolScreen(
            toolCardIdentifier: "quickAction_button_speedTest",
            expectedScreenIdentifier: "screen_speedTestTool",
            fileName: "05-speed-test"
        )

        // 6) World Ping
        captureToolScreen(
            toolCardIdentifier: "tools_card_world_ping",
            expectedScreenIdentifier: "screen_worldPingTool",
            fileName: "06-world-ping"
        )

        // 7) Ping
        captureToolScreen(
            toolCardIdentifier: "tools_card_ping",
            expectedScreenIdentifier: "screen_pingTool",
            fileName: "07-ping"
        )

        // 8) Web Browser
        captureToolScreen(
            toolCardIdentifier: "tools_card_web_browser",
            expectedScreenIdentifier: "screen_webBrowser",
            fileName: "08-web-browser"
        )

        // 9) Timeline
        openTab("Timeline", expectedScreen: "screen_networkTimeline")
        capture("09-timeline")

        // 10) Settings
        openTab("Dashboard", expectedScreen: "screen_dashboard")
        let settingsButton = app.buttons["dashboard_button_settings"]
        requireExists(settingsButton, timeout: 5, message: "Expected Settings button on Dashboard")
        settingsButton.tap()
        XCTAssertTrue(ui("screen_settings").waitForExistence(timeout: 5))
        pauseForAnimation()
        capture("10-settings")
    }

    // MARK: - Helpers

    private func prepareOutputDirectory() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private func openTab(_ tabName: String, expectedScreen: String) {
        let tab = app.tabBars.buttons[tabName]
        requireExists(tab, timeout: 5, message: "Expected tab \(tabName)")
        tab.tap()
        XCTAssertTrue(
            ui(expectedScreen).waitForExistence(timeout: 8),
            "Expected screen \(expectedScreen) after selecting \(tabName)"
        )
        pauseForAnimation()
    }

    private func captureToolScreen(
        toolCardIdentifier: String,
        expectedScreenIdentifier: String,
        fileName: String
    ) {
        openTab("Tools", expectedScreen: "screen_tools")

        let card = toolCard(toolCardIdentifier)
        scrollToElement(card, maxSwipes: 8)
        requireExists(card, timeout: 3, message: "Expected tool card \(toolCardIdentifier)")
        card.tap()

        XCTAssertTrue(
            ui(expectedScreenIdentifier).waitForExistence(timeout: 8),
            "Expected screen \(expectedScreenIdentifier)"
        )
        pauseForAnimation()
        capture(fileName)
        navigateBackFromTool()
    }

    private func navigateBackFromTool() {
        let backButton = app.navigationBars.buttons.firstMatch
        requireExists(backButton, timeout: 5, message: "Expected navigation back button")
        backButton.tap()
        XCTAssertTrue(ui("screen_tools").waitForExistence(timeout: 8))
        pauseForAnimation()
    }

    private func pauseForAnimation() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let fileURL = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: fileURL)
        } catch {
            XCTFail("Failed to save screenshot \(name): \(error)")
        }
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func toolCard(_ identifier: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR identifier CONTAINS %@", identifier, identifier)
        ).firstMatch
    }
}
