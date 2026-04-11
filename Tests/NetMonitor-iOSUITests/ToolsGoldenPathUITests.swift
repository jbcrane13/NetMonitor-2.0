import XCTest

/// Golden path tests for all 14 network tools.
///
/// Each test:
///   1. Opens the tool from the Tools grid
///   2. Verifies the screen and its key controls render
///   3. Triggers the tool's primary action (input + run / open / calculate)
///   4. Asserts that the tool enters a recognisable active or result state
///
/// Network-dependent assertions accept any visible outcome (running indicator,
/// loading state, error banner, or actual results) so the suite is not flaky
/// in simulator environments without live internet access.
final class ToolsGoldenPathUITests: IOSUITestCase {

    // MARK: - 1. Ping

    func testPingGoldenPath() {
        openTool(card: "tools_card_ping", screen: "screen_pingTool")

        let runButton = requireExists(
            app.buttons["pingTool_button_run"],
            message: "Ping: run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Ping: run should be disabled without a host")

        clearAndTypeText("127.0.0.1", into: app.textFields["pingTool_input_host"])
        XCTAssertTrue(runButton.isEnabled, "Ping: run should be enabled after entering a host")

        runButton.tap()
        XCTAssertTrue(
            waitForEither([
                app.buttons["Stop Ping"],
                ui("pingTool_section_results"),
                app.staticTexts["pingTool_error"]
            ], timeout: 15),
            "Ping: should enter running state or show results"
        )
    }

    // MARK: - 2. Traceroute

    func testTracerouteGoldenPath() {
        openTool(card: "tools_card_traceroute", screen: "screen_tracerouteTool")

        let runButton = requireExists(
            app.buttons["tracerouteTool_button_run"],
            message: "Traceroute: run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Traceroute: run should be disabled without a host")

        clearAndTypeText("1.1.1.1", into: app.textFields["tracerouteTool_input_host"])
        XCTAssertTrue(runButton.isEnabled, "Traceroute: run should be enabled after entering a host")

        runButton.tap()
        XCTAssertTrue(
            waitForEither([
                app.buttons["Stop Trace"],
                ui("tracerouteTool_section_hops"),
                app.staticTexts["tracerouteTool_error"]
            ], timeout: 20),
            "Traceroute: should enter running state or show hop results"
        )
    }

    // MARK: - 3. DNS Lookup

    func testDNSLookupGoldenPath() {
        openTool(card: "tools_card_dns_lookup", screen: "screen_dnsLookupTool")

        let runButton = requireExists(
            app.buttons["dnsLookup_button_run"],
            message: "DNS Lookup: run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "DNS Lookup: run should be disabled without a domain")

        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        XCTAssertTrue(runButton.isEnabled, "DNS Lookup: run should be enabled after entering a domain")

        runButton.tap()
        XCTAssertTrue(
            waitForEither([
                app.buttons["Looking up..."],
                ui("dnsLookup_section_queryInfo"),
                ui("dnsLookup_label_error"),
                app.buttons["dnsLookup_button_clear"]
            ], timeout: 20),
            "DNS Lookup: should enter loading state or show results/error"
        )
    }

    // MARK: - 4. Port Scanner

    func testPortScannerGoldenPath() {
        openTool(card: "tools_card_port_scanner", screen: "screen_portScannerTool")

        let runButton = requireExists(
            app.buttons["portScanner_button_run"],
            message: "Port Scanner: run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Port Scanner: run should be disabled without a host")

        clearAndTypeText("127.0.0.1", into: app.textFields["portScanner_input_host"])
        XCTAssertTrue(runButton.isEnabled, "Port Scanner: run should be enabled after entering a host")

        runButton.tap()
        XCTAssertTrue(
            waitForEither([
                ui("portScanner_progress"),
                app.buttons["Stop Scan"],
                ui("portScanner_section_results")
            ], timeout: 15),
            "Port Scanner: should enter running state or show results"
        )
    }

    // MARK: - 5. Web Browser

    func testWebBrowserGoldenPath() {
        openTool(card: "tools_card_web_browser", screen: "screen_webBrowser")

        let openButton = requireExists(
            app.buttons["webBrowser_button_open"],
            message: "Web Browser: open button should exist"
        )
        XCTAssertFalse(openButton.isEnabled, "Web Browser: open should be disabled with empty URL")

        requireExists(
            ui("webBrowser_section_bookmarks"),
            message: "Web Browser: bookmarks section should be visible"
        )

        clearAndTypeText("https://example.com", into: app.textFields["webBrowser_input_url"])
        XCTAssertTrue(openButton.isEnabled, "Web Browser: open should be enabled after entering URL")
    }

    // MARK: - 6. Bonjour Discovery

    func testBonjourGoldenPath() {
        openTool(card: "tools_card_bonjour", screen: "screen_bonjourTool")

        let runButton = requireExists(
            app.buttons["bonjour_button_run"],
            message: "Bonjour: run button should exist"
        )
        runButton.tap()

        XCTAssertTrue(
            waitForEither([
                app.staticTexts["Discovering services..."],
                ui("bonjour_section_services"),
                ui("bonjour_label_noServices")
            ], timeout: 12),
            "Bonjour: should enter discovering state or show services/empty state"
        )
    }

    // MARK: - 7. Speed Test

    func testSpeedTestGoldenPath() {
        openTool(card: "tools_card_speed_test", screen: "screen_speedTestTool")

        requireExists(
            app.segmentedControls["speedTest_picker_duration"],
            message: "Speed Test: duration picker should exist"
        )
        let runButton = requireExists(
            app.buttons["speedTest_button_run"],
            message: "Speed Test: run button should exist"
        )

        runButton.tap()
        XCTAssertTrue(
            waitForEither([
                app.buttons["Stop Test"],
                app.staticTexts["Measuring latency..."],
                app.staticTexts["Testing download..."],
                app.staticTexts["Testing upload..."],
                app.staticTexts["Complete"]
            ], timeout: 12),
            "Speed Test: should enter an active phase after tapping Start"
        )
    }

    // MARK: - 8. WHOIS

    func testWHOISGoldenPath() {
        openTool(card: "tools_card_whois", screen: "screen_whoisTool")

        let runButton = requireExists(
            app.buttons["whois_button_run"],
            message: "WHOIS: run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "WHOIS: run should be disabled without a domain")

        clearAndTypeText("example.com", into: app.textFields["whois_input_domain"])
        XCTAssertTrue(runButton.isEnabled, "WHOIS: run should be enabled after entering a domain")

        runButton.tap()
        XCTAssertTrue(
            waitForEither([
                app.buttons["Looking up..."],
                ui("whois_section_domainInfo"),
                ui("whois_label_error"),
                app.buttons["whois_button_clear"]
            ], timeout: 20),
            "WHOIS: should enter loading state or show results/error"
        )
    }

    // MARK: - 9. Wake on LAN

    func testWakeOnLANGoldenPath() {
        openTool(card: "tools_card_wake_on_lan", screen: "screen_wolTool")

        let sendButton = requireExists(
            app.buttons["wol_button_send"],
            message: "Wake on LAN: send button should exist"
        )
        XCTAssertFalse(sendButton.isEnabled, "Wake on LAN: send should be disabled without a MAC")

        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: app.textFields["wol_input_mac"])
        XCTAssertTrue(sendButton.isEnabled, "Wake on LAN: send should be enabled with a valid MAC")

        requireExists(
            app.staticTexts["Valid MAC address"],
            message: "Wake on LAN: valid MAC indicator should appear"
        )

        sendButton.tap()
        XCTAssertTrue(
            waitForEither([
                app.buttons["Sending..."],
                app.staticTexts["Wake packet sent!"],
                app.staticTexts["Failed to send"]
            ], timeout: 8),
            "Wake on LAN: should show sending state or final result"
        )
    }

    // MARK: - 10. Subnet Calculator

    func testSubnetCalculatorGoldenPath() {
        openTool(card: "tools_card_subnet_calc", screen: "screen_subnetCalculatorTool")

        let calculateButton = requireExists(
            app.buttons["subnetTool_button_calculate"],
            message: "Subnet Calc: calculate button should exist"
        )
        XCTAssertFalse(calculateButton.isEnabled, "Subnet Calc: calculate should be disabled without input")

        clearAndTypeText("10.0.0.0/8", into: app.textFields["subnetTool_input_cidr"])
        XCTAssertTrue(calculateButton.isEnabled, "Subnet Calc: calculate should be enabled after entering CIDR")

        calculateButton.tap()
        requireExists(
            ui("subnetTool_section_results"),
            timeout: 8,
            message: "Subnet Calc: results section should appear after valid CIDR calculation"
        )
    }

    // MARK: - 11. World Ping

    func testWorldPingGoldenPath() {
        openTool(card: "tools_card_world_ping", screen: "screen_worldPingTool")

        let runButton = requireExists(
            app.buttons["worldPing_button_run"],
            message: "World Ping: run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "World Ping: run should be disabled without a host")

        clearAndTypeText("google.com", into: app.textFields["worldPing_textfield_host"])
        XCTAssertTrue(runButton.isEnabled, "World Ping: run should be enabled after entering a host")

        runButton.tap()
        XCTAssertTrue(
            waitForEither([
                ui("worldPing_section_results"),
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] 'pinging' OR label CONTAINS[c] 'checking'")
                ).firstMatch,
                ui("worldPing_row")
            ], timeout: 20),
            "World Ping: should enter running state or show location results"
        )
    }

    // MARK: - 12. Geo Trace

    func testGeoTraceGoldenPath() {
        openTool(card: "tools_card_geo_trace", screen: "screen_geoTrace")

        requireExists(
            ui("geoTrace_map"),
            message: "Geo Trace: map view should be visible"
        )
        let traceButton = requireExists(
            app.buttons["geoTrace_button_trace"],
            message: "Geo Trace: trace button should exist"
        )
        XCTAssertFalse(traceButton.isEnabled, "Geo Trace: trace should be disabled without a host")

        clearAndTypeText("8.8.8.8", into: app.textFields["geoTrace_textfield_host"])
        XCTAssertTrue(traceButton.isEnabled, "Geo Trace: trace should be enabled after entering a host")

        traceButton.tap()
        let stopButton = app.buttons["geoTrace_button_stop"]
        let hopAnnotation = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'geoTrace_hop_'")
        ).firstMatch
        let anyOutcome = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'hop' OR label CONTAINS[c] 'unreachable' OR label CONTAINS[c] 'timeout'")
        ).firstMatch

        let deadline = Date().addingTimeInterval(15)
        var found = false
        while Date() < deadline {
            if stopButton.exists || hopAnnotation.exists || anyOutcome.exists {
                found = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(found, "Geo Trace: should produce a visible outcome after tapping Trace")
    }

    // MARK: - 13. SSL Certificate Monitor

    func testSSLMonitorGoldenPath() {
        openTool(card: "tools_card_ssl_monitor", screen: "screen_sslCertificateMonitor")

        requireExists(
            ui("sslMonitor_picker_view"),
            message: "SSL Monitor: view picker (Query / Watch List) should exist"
        )
        let queryButton = requireExists(
            app.buttons["sslMonitor_button_query"],
            message: "SSL Monitor: query button should exist"
        )
        XCTAssertFalse(queryButton.isEnabled, "SSL Monitor: query should be disabled with empty domain")

        clearAndTypeText("example.com", into: app.textFields["sslMonitor_textfield_domain"])
        XCTAssertTrue(queryButton.isEnabled, "SSL Monitor: query should be enabled after entering a domain")

        queryButton.tap()
        XCTAssertTrue(
            waitForEither([
                ui("sslMonitor_card_ssl"),
                ui("sslMonitor_card_whois"),
                ui("sslMonitor_label_error"),
                app.buttons["sslMonitor_button_add"]
            ], timeout: 20),
            "SSL Monitor: should show certificate info, WHOIS info, or error after querying"
        )
    }

    // MARK: - Helpers

    private func openTool(card cardID: String, screen screenID: String) {
        requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist").tap()
        requireExists(ui("screen_tools"), timeout: 8, message: "Tools screen should appear")
        let card = ui(cardID)
        scrollToElement(card)
        requireExists(card, timeout: 8, message: "\(cardID) should exist in tools grid").tap()
        requireExists(ui(screenID), timeout: 8, message: "\(screenID) should appear after opening \(cardID)")
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
