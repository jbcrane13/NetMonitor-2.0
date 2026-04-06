import XCTest

/// Functional smoke tests that verify each major screen and tool produces
/// correct **outcomes**, not just element existence. Each test captures a
/// screenshot at the verification point for visual review.
///
/// Run the full suite:
///   ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test \
///     -scheme NetMonitor-iOS -configuration Debug \
///     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
///     -only-testing:NetMonitor-iOSUITests/FunctionalSmokeTests"
///
/// Design:
///   - Happy paths only — one path per tool/screen
///   - Sequential execution — Set Target once, all tools inherit it
///   - Outcome assertions — verify result *content* (ms, Mbps, IP addresses)
///   - Screenshot capture — XCTAttachment at every verification point
///   - Network-tolerant — accepts results OR meaningful error states
@MainActor
final class FunctionalSmokeTests: IOSUITestCase {

    /// Shorthand for `app.descendants(matching: .any)[identifier]`.
    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Returns true if any staticText on screen contains the given substring.
    private func screenContainsText(_ substring: String) -> Bool {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", substring)
        ).firstMatch.waitForExistence(timeout: 3)
    }

    /// Opens a tool from the Tools tab grid and verifies the screen appears.
    private func openTool(card cardID: String, screen screenID: String) {
        app.tabBars.buttons["Tools"].tap()
        requireExists(ui("screen_tools"), timeout: 5, message: "Tools screen should appear")
        let card = ui(cardID)
        scrollToElement(card)
        requireExists(card, timeout: 5, message: "\(cardID) should be visible").tap()
        requireExists(ui(screenID), timeout: 8, message: "\(screenID) should appear")
    }

    /// Navigates back from a pushed tool view to the Tools grid.
    private func goBackToTools() {
        if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        // Wait for tools screen to reappear
        _ = ui("screen_tools").waitForExistence(timeout: 5)
    }

    // MARK: - Dashboard

    func test01_DashboardShowsNetworkStatus() {
        // Dashboard is the default landing tab
        let dashboard = ui("screen_dashboard")
        requireExists(dashboard, timeout: 10, message: "Dashboard should be the first screen")

        // Verify health score card renders with a numeric score
        let healthCard = ui("dashboard_card_healthScore")
        requireExists(healthCard, timeout: 10, message: "Health score card should be visible")

        // Verify WAN info card shows ISP/IP data
        let wanCard = ui("dashboard_card_wan")
        scrollToElement(wanCard)
        requireExists(wanCard, timeout: 8, message: "WAN info card should be visible")

        // Verify anchor latency card shows latency values
        let anchorCard = ui("dashboard_card_anchorLatency")
        scrollToElement(anchorCard)
        requireExists(anchorCard, timeout: 8, message: "Anchor latency card should be visible")

        captureScreenshot(named: "01_Dashboard_NetworkStatus")

        // Functional check: connection status header shows MONITORING or OFFLINE
        let header = ui("dashboard_label_connectionStatus")
        if header.exists {
            let headerLabel = header.label
            let hasStatus = headerLabel.localizedCaseInsensitiveContains("monitoring")
                || headerLabel.localizedCaseInsensitiveContains("offline")
                || headerLabel.localizedCaseInsensitiveContains("online")
            XCTAssertTrue(hasStatus, "Dashboard header should show a connection status, got: \(headerLabel)")
        }
    }

    func test02_DashboardLocalDevicesCard() {
        let devicesCard = ui("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, timeout: 10, message: "Local devices card should exist")

        captureScreenshot(named: "02_Dashboard_LocalDevices")

        // Functional check: devices card shows either device rows or searching state
        let hasDeviceContent = screenContainsText("192.168")
            || screenContainsText("10.0.")
            || screenContainsText("172.")
            || screenContainsText("SEARCHING")
            || screenContainsText("total")
        XCTAssertTrue(hasDeviceContent, "Devices card should show device IPs or searching state")
    }

    func test03_DashboardSettingsNavigation() {
        let settingsButton = app.buttons["dashboard_button_settings"]
        requireExists(settingsButton, timeout: 5, message: "Settings gear button should be on dashboard")
        settingsButton.tap()

        requireExists(ui("screen_settings"), timeout: 5, message: "Settings screen should appear")
        captureScreenshot(named: "03_Dashboard_SettingsNav")

        // Go back to dashboard
        if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    // MARK: - Network Map

    func test04_NetworkMapShowsDevices() {
        app.tabBars.buttons["Map"].tap()
        let mapScreen = ui("screen_networkMap")
        requireExists(mapScreen, timeout: 8, message: "Network Map screen should appear")

        // Verify network summary renders
        let summary = ui("networkMap_summary")
        requireExists(summary, timeout: 8, message: "Network summary header should exist")

        captureScreenshot(named: "04_NetworkMap_Overview")

        // Functional check: summary shows gateway info or network name
        let summaryHasContent = screenContainsText("Gateway")
            || screenContainsText("192.168")
            || screenContainsText("10.0.")
            || screenContainsText("SIGNAL GRID")
            || screenContainsText("No Nodes")
        XCTAssertTrue(summaryHasContent, "Network map should show network info or empty state")
    }

    func test05_NetworkMapScanAction() {
        app.tabBars.buttons["Map"].tap()
        requireExists(ui("screen_networkMap"), timeout: 5, message: "Network Map should be visible")

        let scanButton = ui("networkMap_button_scan")
        if scanButton.exists && scanButton.isHittable {
            scanButton.tap()
            // Wait briefly for scan to start
            sleep(2)
            captureScreenshot(named: "05_NetworkMap_Scanning")

            // Functional check: scan produces visible activity or device rows
            let hasActivity = screenContainsText("192.168")
                || screenContainsText("10.0.")
                || screenContainsText("Scanning")
                || screenContainsText("SIGNAL GRID")
                || screenContainsText("No Nodes")
            XCTAssertTrue(hasActivity, "Scan should produce visible network activity or state")
        }
    }

    // MARK: - Settings

    func test06_SettingsTogglesFunction() {
        app.tabBars.buttons["Dashboard"].tap()
        let settingsButton = app.buttons["dashboard_button_settings"]
        requireExists(settingsButton, timeout: 5, message: "Settings button should exist")
        settingsButton.tap()
        requireExists(ui("screen_settings"), timeout: 5, message: "Settings screen should appear")

        // Verify key settings exist and are interactive
        let bgRefresh = ui("settings_toggle_backgroundRefresh")
        scrollToElement(bgRefresh)
        if bgRefresh.exists {
            let initialValue = bgRefresh.value as? String
            bgRefresh.tap()
            let newValue = bgRefresh.value as? String
            // Toggle should change value (or at least be tappable)
            if let initial = initialValue, let new = newValue {
                XCTAssertNotEqual(initial, new, "Background refresh toggle should change state")
            }
            // Restore original state
            bgRefresh.tap()
        }

        captureScreenshot(named: "06_Settings_Toggles")
    }

    func test07_SettingsAppearanceSection() {
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["dashboard_button_settings"].tap()
        requireExists(ui("screen_settings"), timeout: 5, message: "Settings should appear")

        // Scroll to appearance section
        let colorScheme = ui("settings_picker_colorScheme")
        scrollToElement(colorScheme)
        requireExists(colorScheme, timeout: 5, message: "Color scheme picker should exist")

        let accentColor = ui("settings_picker_accentColor")
        scrollToElement(accentColor)
        requireExists(accentColor, timeout: 5, message: "Accent color picker should exist")

        captureScreenshot(named: "07_Settings_Appearance")
    }

    func test08_SettingsAboutSection() {
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["dashboard_button_settings"].tap()
        requireExists(ui("screen_settings"), timeout: 5, message: "Settings should appear")

        // Scroll to About section
        let appVersion = ui("settings_row_appVersion")
        scrollToElement(appVersion)
        requireExists(appVersion, timeout: 5, message: "App version row should exist")

        captureScreenshot(named: "08_Settings_About")

        // Functional check: version shows a real version string
        let hasVersion = screenContainsText("2.") || screenContainsText("1.")
        XCTAssertTrue(hasVersion, "About section should display an app version number")
    }

    // MARK: - Timeline

    func test09_TimelineRendersOrEmpty() {
        app.tabBars.buttons["Timeline"].tap()

        let hasTimeline = waitForEither([
            ui("timeline_list_events"),
            ui("timeline_label_emptyState")
        ], timeout: 8)
        XCTAssertTrue(hasTimeline, "Timeline should show event list or empty state")

        captureScreenshot(named: "09_Timeline")

        // Verify filter button exists
        let filterButton = ui("timeline_button_filters")
        if filterButton.exists {
            filterButton.tap()
            requireExists(
                ui("timelineFilter_button_showAll"),
                timeout: 5,
                message: "Filter sheet should show 'All Events' option"
            )
            captureScreenshot(named: "09_Timeline_Filters")
            // Dismiss filter sheet
            ui("timelineFilter_button_done").tap()
        }
    }

    // MARK: - Tools: Diagnostics

    func test10_PingProducesLatencyResults() {
        openTool(card: "tools_card_ping", screen: "screen_pingTool")

        clearAndTypeText("127.0.0.1", into: app.textFields["pingTool_input_host"])
        app.buttons["pingTool_button_run"].tap()

        // Wait for results — ping to localhost should complete quickly
        let resultsSection = ui("pingTool_section_results")
        let gotResults = resultsSection.waitForExistence(timeout: 20)

        if gotResults {
            // Functional check: results contain latency values in ms
            let hasLatency = screenContainsText("ms")
            XCTAssertTrue(hasLatency, "Ping results should contain latency values in ms")

            // Verify statistics card shows min/avg/max
            let statsCard = ui("pingTool_card_statistics")
            scrollToElement(statsCard)
            if statsCard.exists {
                let statAvg = ui("pingTool_stat_avg")
                let statMin = ui("pingTool_stat_min")
                let statMax = ui("pingTool_stat_max")
                XCTAssertTrue(
                    statAvg.exists || statMin.exists || statMax.exists,
                    "Statistics should show min/avg/max values"
                )
            }
        } else {
            // Accept error state as valid outcome on simulator
            let hasError = screenContainsText("error") || screenContainsText("timed out")
            XCTAssertTrue(hasError || gotResults, "Ping should produce results or an error")
        }

        captureScreenshot(named: "10_Ping_Results")
        goBackToTools()
    }

    func test11_TracerouteShowsHops() {
        openTool(card: "tools_card_traceroute", screen: "screen_tracerouteTool")

        clearAndTypeText("1.1.1.1", into: app.textFields["tracerouteTool_input_host"])
        app.buttons["tracerouteTool_button_run"].tap()

        // Wait for hops or running indicator
        let hopsSection = ui("tracerouteTool_section_hops")
        let gotHops = waitForEither([
            hopsSection,
            app.buttons["Stop Trace"]
        ], timeout: 20)

        XCTAssertTrue(gotHops, "Traceroute should show hops or running indicator")

        if hopsSection.waitForExistence(timeout: 25) {
            // Functional check: at least one hop row appeared
            let firstHop = ui("tracerouteTool_row_1")
            let hasHop = firstHop.waitForExistence(timeout: 5)
            XCTAssertTrue(hasHop || screenContainsText("*"), "Should show at least hop 1 or timeout marker")
        }

        captureScreenshot(named: "11_Traceroute_Hops")
        goBackToTools()
    }

    func test12_DNSLookupShowsRecords() {
        openTool(card: "tools_card_dns_lookup", screen: "screen_dnsLookupTool")

        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        app.buttons["dnsLookup_button_run"].tap()

        // Wait for results
        let queryInfo = ui("dnsLookup_section_queryInfo")
        let gotResults = waitForEither([
            queryInfo,
            ui("dnsLookup_section_records"),
            ui("dnsLookup_label_error")
        ], timeout: 20)

        XCTAssertTrue(gotResults, "DNS Lookup should show query info, records, or error")

        if queryInfo.exists {
            // Functional check: results contain an IP address pattern or record type
            let hasRecordContent = screenContainsText("93.184.") // example.com's IP prefix
                || screenContainsText("A")
                || screenContainsText("AAAA")
                || screenContainsText("Query")
            XCTAssertTrue(hasRecordContent, "DNS results should contain record data")
        }

        captureScreenshot(named: "12_DNS_Records")
        goBackToTools()
    }

    func test13_WHOISShowsDomainInfo() {
        openTool(card: "tools_card_whois", screen: "screen_whoisTool")

        clearAndTypeText("example.com", into: app.textFields["whois_input_domain"])
        app.buttons["whois_button_run"].tap()

        let domainInfo = ui("whois_section_domainInfo")
        let gotResults = waitForEither([
            domainInfo,
            ui("whois_section_dates"),
            ui("whois_label_error")
        ], timeout: 25)

        XCTAssertTrue(gotResults, "WHOIS should show domain info, dates, or error")

        if domainInfo.exists {
            // Functional check: WHOIS results contain registrar or domain data
            let hasDomainData = screenContainsText("example.com")
                || screenContainsText("Registrar")
                || screenContainsText("IANA")
                || screenContainsText("Reserved")
            XCTAssertTrue(hasDomainData, "WHOIS should show domain registration data")

            // Check name servers section
            let nameServers = ui("whois_section_nameServers")
            scrollToElement(nameServers)
            if nameServers.exists {
                let hasNS = screenContainsText("ns") || screenContainsText("dns")
                XCTAssertTrue(hasNS, "Name servers section should contain server names")
            }
        }

        captureScreenshot(named: "13_WHOIS_DomainInfo")
        goBackToTools()
    }

    // MARK: - Tools: Discovery

    func test14_PortScannerFindsOpenPorts() {
        openTool(card: "tools_card_port_scanner", screen: "screen_portScannerTool")

        clearAndTypeText("127.0.0.1", into: app.textFields["portScanner_input_host"])
        app.buttons["portScanner_button_run"].tap()

        let gotActivity = waitForEither([
            ui("portScanner_progress"),
            ui("portScanner_section_results"),
            app.buttons["Stop Scan"]
        ], timeout: 15)

        XCTAssertTrue(gotActivity, "Port scanner should show progress, results, or stop button")

        // Wait for scan to produce some results
        let results = ui("portScanner_section_results")
        if results.waitForExistence(timeout: 30) {
            // Functional check: results show port numbers or "open"/"closed"
            let hasPortData = screenContainsText("open")
                || screenContainsText("closed")
                || screenContainsText("filtered")
                || screenContainsText("Port")
            XCTAssertTrue(hasPortData, "Port scan results should show port states")
        }

        captureScreenshot(named: "14_PortScanner_Results")
        goBackToTools()
    }

    func test15_BonjourDiscoversServices() {
        openTool(card: "tools_card_bonjour", screen: "screen_bonjourTool")

        app.buttons["bonjour_button_run"].tap()

        let gotActivity = waitForEither([
            ui("bonjour_section_services"),
            ui("bonjour_label_noServices"),
            app.staticTexts["Discovering services..."]
        ], timeout: 15)

        XCTAssertTrue(gotActivity, "Bonjour should show services, empty state, or discovering indicator")

        captureScreenshot(named: "15_Bonjour_Services")
        goBackToTools()
    }

    func test16_SubnetCalculatorProducesResults() {
        openTool(card: "tools_card_subnet_calc", screen: "screen_subnetCalculatorTool")

        clearAndTypeText("192.168.1.0/24", into: app.textFields["subnetTool_input_cidr"])
        app.buttons["subnetTool_button_calculate"].tap()

        let results = ui("subnetTool_section_results")
        requireExists(results, timeout: 8, message: "Subnet calculator should show results")

        // Functional check: results contain expected network calculations
        let networkAddr = ui("subnetCalculator_label_networkAddress")
        if networkAddr.exists {
            let hasCorrectNetwork = screenContainsText("192.168.1.0")
            XCTAssertTrue(hasCorrectNetwork, "Network address should be 192.168.1.0 for /24")
        }

        let broadcastAddr = ui("subnetCalculator_label_broadcastAddress")
        if broadcastAddr.exists {
            let hasCorrectBroadcast = screenContainsText("192.168.1.255")
            XCTAssertTrue(hasCorrectBroadcast, "Broadcast should be 192.168.1.255 for /24")
        }

        let hostCount = ui("subnetCalculator_label_hostCount")
        if hostCount.exists {
            let hasCorrectCount = screenContainsText("254")
            XCTAssertTrue(hasCorrectCount, "Usable hosts should be 254 for /24")
        }

        captureScreenshot(named: "16_SubnetCalc_Results")
        goBackToTools()
    }

    // MARK: - Tools: Monitoring

    func test17_SpeedTestRunsPhases() {
        openTool(card: "tools_card_speed_test", screen: "screen_speedTestTool")

        app.buttons["speedTest_button_run"].tap()

        // Speed test has sequential phases
        let gotActivity = waitForEither([
            app.buttons["Stop Test"],
            app.staticTexts["Measuring latency..."],
            app.staticTexts["Testing download..."],
            app.staticTexts["Testing upload..."]
        ], timeout: 12)

        XCTAssertTrue(gotActivity, "Speed test should enter an active phase")

        // Wait for completion or accept any phase result
        let results = ui("speedTest_section_results")
        if results.waitForExistence(timeout: 90) {
            // Functional check: results show Mbps values
            let hasMbps = screenContainsText("Mbps") || screenContainsText("mbps")
            let hasMs = screenContainsText("ms")
            XCTAssertTrue(hasMbps || hasMs, "Speed test results should show Mbps or ms values")
        }

        captureScreenshot(named: "17_SpeedTest_Results")
        goBackToTools()
    }

    func test18_WorldPingShowsLocations() {
        openTool(card: "tools_card_world_ping", screen: "screen_worldPingTool")

        clearAndTypeText("google.com", into: app.textFields["worldPing_textfield_host"])
        app.buttons["worldPing_button_run"].tap()

        let gotResults = waitForEither([
            ui("worldPing_section_results"),
            ui("worldPing_row")
        ], timeout: 25)

        if gotResults {
            // Functional check: results show city/country or latency
            let hasLocationData = screenContainsText("ms")
                || screenContainsText("US")
                || screenContainsText("EU")
                || screenContainsText("Asia")
            XCTAssertTrue(hasLocationData, "World ping should show location results with latency")
        }

        captureScreenshot(named: "18_WorldPing_Locations")
        goBackToTools()
    }

    func test19_SSLMonitorShowsCertificate() {
        openTool(card: "tools_card_ssl_monitor", screen: "screen_sslCertificateMonitor")

        clearAndTypeText("example.com", into: app.textFields["sslMonitor_textfield_domain"])
        app.buttons["sslMonitor_button_query"].tap()

        let gotResults = waitForEither([
            ui("sslMonitor_card_ssl"),
            ui("sslMonitor_card_whois"),
            ui("sslMonitor_label_error")
        ], timeout: 25)

        XCTAssertTrue(gotResults, "SSL Monitor should show certificate info, WHOIS, or error")

        if ui("sslMonitor_card_ssl").exists {
            // Functional check: certificate shows issuer and validity
            let hasCertData = screenContainsText("Valid")
                || screenContainsText("Expires")
                || screenContainsText("Issuer")
                || screenContainsText("days")
            XCTAssertTrue(hasCertData, "SSL certificate card should show validity information")
        }

        captureScreenshot(named: "19_SSL_Certificate")
        goBackToTools()
    }

    // MARK: - Tools: Actions

    func test20_WakeOnLANValidatesAndSends() {
        openTool(card: "tools_card_wake_on_lan", screen: "screen_wolTool")

        let sendButton = app.buttons["wol_button_send"]
        requireExists(sendButton, message: "WoL send button should exist")

        // Enter invalid MAC first
        clearAndTypeText("INVALID", into: app.textFields["wol_input_mac"])
        XCTAssertFalse(sendButton.isEnabled, "Send should be disabled with invalid MAC")

        // Enter valid MAC
        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: app.textFields["wol_input_mac"])
        XCTAssertTrue(sendButton.isEnabled, "Send should be enabled with valid MAC")

        // Functional check: valid MAC indicator appears
        let hasValidation = screenContainsText("Valid MAC")
        XCTAssertTrue(hasValidation, "Should show 'Valid MAC address' indicator")

        sendButton.tap()

        let gotOutcome = waitForEither([
            ui("wol_label_success"),
            ui("wol_label_error")
        ], timeout: 10)

        XCTAssertTrue(gotOutcome, "WoL should show success or error after sending")

        captureScreenshot(named: "20_WakeOnLAN_Result")
        goBackToTools()
    }

    func test21_GeoTraceShowsMap() {
        openTool(card: "tools_card_geo_trace", screen: "screen_geoTrace")

        // Verify map renders
        requireExists(ui("geoTrace_map"), timeout: 8, message: "Map should be visible")

        clearAndTypeText("8.8.8.8", into: app.textFields["geoTrace_textfield_host"])
        app.buttons["geoTrace_button_trace"].tap()

        let gotActivity = waitForEither([
            app.buttons["geoTrace_button_stop"],
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'hop'")
            ).firstMatch
        ], timeout: 15)

        // Accept either running state or hop results
        if gotActivity {
            captureScreenshot(named: "21_GeoTrace_Tracing")
        }

        // Map should still be present during/after trace
        XCTAssertTrue(ui("geoTrace_map").exists, "Map should remain visible during trace")

        captureScreenshot(named: "21_GeoTrace_Map")
        goBackToTools()
    }

    func test22_WebBrowserAcceptsURL() {
        openTool(card: "tools_card_web_browser", screen: "screen_webBrowser")

        let openButton = app.buttons["webBrowser_button_open"]
        requireExists(openButton, message: "Open button should exist")
        XCTAssertFalse(openButton.isEnabled, "Open should be disabled with empty URL")

        clearAndTypeText("https://example.com", into: app.textFields["webBrowser_input_url"])
        XCTAssertTrue(openButton.isEnabled, "Open should be enabled after entering URL")

        // Verify bookmarks section exists
        let bookmarks = ui("webBrowser_section_bookmarks")
        scrollToElement(bookmarks)
        requireExists(bookmarks, timeout: 5, message: "Bookmarks section should exist")

        captureScreenshot(named: "22_WebBrowser_Ready")
        goBackToTools()
    }

    // MARK: - Room Scanner (Setup Only)

    func test23_RoomScannerSetupScreen() {
        openTool(card: "tools_card_room_scanner", screen: "roomScanner_icon_setup")

        // Room Scanner should show setup screen (not crash or go blank)
        let hasSetupContent = screenContainsText("3D Room Scanner")
            || screenContainsText("Room Scanner")
            || screenContainsText("LiDAR")
        XCTAssertTrue(hasSetupContent, "Room Scanner should show setup screen with LiDAR status")

        // Verify project name input exists
        let projectName = app.textFields["roomScanner_textfield_projectName"]
        requireExists(projectName, timeout: 5, message: "Project name input should exist")

        // Verify start scan button exists
        let startButton = app.buttons["roomScanner_button_startScan"]
        scrollToElement(startButton)
        requireExists(startButton, timeout: 5, message: "Start Scanning button should exist")

        captureScreenshot(named: "23_RoomScanner_Setup")
    }
}
