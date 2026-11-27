import XCTest

/// Runs every macOS tool once against a real target and captures a screenshot of the result,
/// for release review (the macOS counterpart of the iOS `FunctionalSmokeTests`). Each test
/// waits for the tool's own result; the screenshot is the evidence of what it showed.
@MainActor
final class MacOSToolSmokeTests: MacOSUITestCase {

    private func run(_ button: String) {
        let element = app.buttons[button]
        requireExists(element, message: "\(button) should exist")
        XCTAssertTrue(element.isEnabled, "\(button) should be enabled")
        element.click()
    }

    private func expectResult(_ elements: [XCUIElement], timeout: TimeInterval, _ message: String) {
        XCTAssertTrue(waitForEither(elements, timeout: timeout), message)
    }

    func test01_Ping() {
        openTool(cardID: "tools_card_ping", sheetElement: "ping_textfield_host")
        clearAndTypeText("1.1.1.1", into: app.textFields["ping_textfield_host"])
        run("ping_button_run")
        expectResult([ui("ping_label_avg")], timeout: 30, "Ping should show statistics")
        captureScreenshot(named: "01_Ping_1.1.1.1")
    }

    func test02_Traceroute() {
        openTool(cardID: "tools_card_traceroute", sheetElement: "traceroute_textfield_host")
        clearAndTypeText("1.1.1.1", into: app.textFields["traceroute_textfield_host"])
        run("traceroute_button_run")
        expectResult([ui("traceroute_row_3")], timeout: 60, "Traceroute should list at least 3 hops")
        RunLoop.current.run(until: Date().addingTimeInterval(5))
        captureScreenshot(named: "02_Traceroute_1.1.1.1")
    }

    func test03_PortScanner() {
        openTool(cardID: "tools_card_port_scanner", sheetElement: "portScan_textfield_host")
        clearAndTypeText("192.168.2.1", into: app.textFields["portScan_textfield_host"])
        run("portScan_button_scan")
        expectResult([ui("portScan_label_openPorts")], timeout: 60, "Port scan should report open ports")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        captureScreenshot(named: "03_PortScanner_gateway")
    }

    func test04_DNSLookup() {
        openTool(cardID: "tools_card_dns_lookup", sheetElement: "dns_textfield_hostname")
        clearAndTypeText("apple.com", into: app.textFields["dns_textfield_hostname"])
        run("dns_button_lookup")
        expectResult([ui("dns_section_results")], timeout: 20, "DNS lookup should show records")
        captureScreenshot(named: "04_DNSLookup_apple.com")
    }

    func test05_WHOIS() {
        openTool(cardID: "tools_card_whois", sheetElement: "whois_textfield_domain")
        clearAndTypeText("apple.com", into: app.textFields["whois_textfield_domain"])
        run("whois_button_lookup")
        expectResult([ui("whois_section_parsed"), app.buttons["whois_button_clear"]], timeout: 30, "WHOIS should show a record")
        captureScreenshot(named: "05_WHOIS_apple.com")
    }

    func test06_SpeedTest() {
        openTool(cardID: "tools_card_speed_test", sheetElement: "speedTest_button_start")
        run("speedTest_button_start")
        XCTAssertTrue(app.buttons["speedTest_button_stop"].waitForExistence(timeout: 8), "Speed test should start")
        // Latency, download and upload; the start button returns when the run completes.
        XCTAssertTrue(waitForDisappearance(app.buttons["speedTest_button_stop"], timeout: 90), "Speed test should finish")
        captureScreenshot(named: "06_SpeedTest_complete")
    }

    func test07_BonjourBrowser() {
        openTool(cardID: "tools_card_bonjour_browser", sheetElement: "bonjour_button_refresh")
        RunLoop.current.run(until: Date().addingTimeInterval(8))
        captureScreenshot(named: "07_Bonjour_services")
    }

    func test08_WakeOnLAN() {
        openTool(cardID: "tools_card_wake_on_lan", sheetElement: "wol_textfield_mac")
        clearAndTypeText("00:11:22:33:44:55", into: app.textFields["wol_textfield_mac"])
        run("wol_button_send")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        captureScreenshot(named: "08_WakeOnLAN_sent")
    }

    func test09_SubnetCalculator() {
        openTool(cardID: "tools_card_subnet_calculator", sheetElement: "subnetCalc_textfield_cidr")
        clearAndTypeText("192.168.2.0/24", into: app.textFields["subnetCalc_textfield_cidr"])
        run("subnetCalc_button_calculate")
        expectResult([ui("subnetCalc_section_results")], timeout: 10, "Subnet calculator should show results")
        captureScreenshot(named: "09_SubnetCalc_192.168.2.0-24")
    }

    func test10_WorldPing() {
        openTool(cardID: "tools_card_world_ping", sheetElement: "worldPing_textfield_host")
        clearAndTypeText("google.com", into: app.textFields["worldPing_textfield_host"])
        run("worldPing_button_run")
        expectResult([ui("worldPing_row_location")], timeout: 60, "World ping should list locations")
        RunLoop.current.run(until: Date().addingTimeInterval(10))
        captureScreenshot(named: "10_WorldPing_google.com")
    }

    func test11_GeoTrace() {
        openTool(cardID: "tools_card_geo_trace", sheetElement: "geoTrace_textfield_host")
        clearAndTypeText("8.8.8.8", into: app.textFields["geoTrace_textfield_host"])
        run("geoTrace_button_trace")
        expectResult([app.buttons["geoTrace_button_clear"]], timeout: 60, "Geo trace should produce hops")
        RunLoop.current.run(until: Date().addingTimeInterval(15))
        captureScreenshot(named: "11_GeoTrace_8.8.8.8")
    }

    func test12_SSLMonitor() {
        openTool(cardID: "tools_card_ssl_monitor", sheetElement: "sslMonitor_textfield_domain")
        clearAndTypeText("apple.com", into: app.textFields["sslMonitor_textfield_domain"])
        run("sslMonitor_button_query")
        expectResult([ui("sslMonitor_card_ssl"), ui("sslMonitor_label_error")], timeout: 30, "SSL monitor should show the certificate")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        captureScreenshot(named: "12_SSLMonitor_apple.com")
    }

    func test13_WiFiHeatmap() {
        navigateToSidebar("tools")
        let card = ui("tools_card_wifi_heatmap").firstMatch
        requireExists(card, message: "WiFi Heatmap card should exist")
        card.click()
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        captureScreenshot(named: "13_WiFiHeatmap_open")
    }

    func test14_PortForwards() {
        openTool(cardID: "tools_card_port_forwards", sheetElement: "portForwards_button_refresh")
        XCTAssertTrue(waitForDisappearance(ui("portForwards_label_loading"), timeout: 30), "Port forwards should finish loading")
        captureScreenshot(named: "14_PortForwards_list")
    }
}
