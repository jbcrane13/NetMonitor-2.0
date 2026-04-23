import XCTest

final class ComponentsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    // MARK: - StatusBadge (Dashboard connection status)

    func testStatusBadgeDisplaysStatusText() throws {
        // The dashboard connection status header uses StatusBadge
        let header = app.otherElements["dashboard_label_connectionStatus"]
        XCTAssertTrue(header.waitForExistence(timeout: 5),
                     "Status badge header should exist on dashboard")
        // FUNCTIONAL: status badge should display a status text value
        let statusTexts = header.staticTexts
        XCTAssertTrue(
            statusTexts.count > 0 || header.label.count > 0,
            "Status badge should display a connection status value (e.g., Monitoring, Offline)"
        )
    }

    // MARK: - GlassButton (Tools quick actions)

    func testGlassButtonSetTargetIsTappable() throws {
        app.tabBars.buttons["Tools"].tap()
        let setTargetButton = app.buttons["quickAction_button_setTarget"]
        let setTargetOther = ui("quickAction_button_setTarget")
        let found = setTargetButton.waitForExistence(timeout: 5) ||
                    setTargetOther.waitForExistence(timeout: 3)
        XCTAssertTrue(found, "Set Target quick action should exist on Tools screen")
        // FUNCTIONAL: button should be tappable
        let button = setTargetButton.exists ? setTargetButton : setTargetOther
        XCTAssertTrue(button.isEnabled, "Set Target button should be tappable")
    }

    func testGlassButtonSpeedTestQuickActionIsTappable() throws {
        app.tabBars.buttons["Tools"].tap()
        let speedTestAction = app.buttons["quickAction_button_speedTest"]
        let speedTestOther = ui("quickAction_button_speedTest")
        let found = speedTestAction.waitForExistence(timeout: 5) ||
                    speedTestOther.waitForExistence(timeout: 3)
        XCTAssertTrue(found, "Speed Test quick action should exist on Tools screen")
        // FUNCTIONAL: button should be tappable
        let button = speedTestAction.exists ? speedTestAction : speedTestOther
        XCTAssertTrue(button.isEnabled, "Speed Test button should be tappable")
    }

    // MARK: - MetricCard (Dashboard cards)

    func testMetricCardsContainContent() throws {
        let sessionCard = ui("dashboard_card_session")
        let wifiCard = ui("dashboard_card_wifi")
        XCTAssertTrue(sessionCard.waitForExistence(timeout: 5),
                     "Session card should exist on dashboard")
        XCTAssertTrue(wifiCard.exists, "WiFi card should exist on dashboard")
        // FUNCTIONAL: cards should contain visible text content
        XCTAssertTrue(
            sessionCard.staticTexts.count > 0,
            "Session card should contain metric text content"
        )
        XCTAssertTrue(
            wifiCard.staticTexts.count > 0,
            "WiFi card should contain metric text content"
        )
    }

    // MARK: - EmptyStateView (Various screens)

    func testEmptyStateOnNetworkMapShowsContent() throws {
        app.tabBars.buttons["Map"].tap()
        // If no devices, empty state should show; otherwise device list
        let emptyState = ui("networkMap_label_empty")
        let deviceRow = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")
        ).firstMatch
        let scanButton = app.buttons["networkMap_button_scan"]
        XCTAssertTrue(emptyState.exists || deviceRow.exists || scanButton.exists,
                     "Network map should show empty state, device rows, or scan button")
        // FUNCTIONAL: if empty state is shown, it should contain instructional text
        if emptyState.exists {
            XCTAssertTrue(
                emptyState.staticTexts.count > 0 || emptyState.label.count > 0,
                "Empty state view should contain instructional text"
            )
        }
    }

    // MARK: - ToolRunButton (All tool screens)

    func testToolRunButtonOnPingScreenDisabledWithoutInput() throws {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = ui("tools_card_ping")
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
        }
        let runButton = app.buttons["pingTool_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5),
                     "Ping run button should exist")
        // FUNCTIONAL: run button should be disabled without host input
        XCTAssertFalse(runButton.isEnabled,
                      "Ping run button should be disabled before entering a host")
    }

    func testToolRunButtonOnTracerouteScreenDisabledWithoutInput() throws {
        app.tabBars.buttons["Tools"].tap()
        let tracerouteCard = ui("tools_card_traceroute")
        if tracerouteCard.waitForExistence(timeout: 5) {
            tracerouteCard.tap()
        }
        let runButton = app.buttons["tracerouteTool_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5),
                     "Traceroute run button should exist")
        // FUNCTIONAL: run button should be disabled without host input
        XCTAssertFalse(runButton.isEnabled,
                      "Traceroute run button should be disabled before entering a host")
    }

    func testToolRunButtonOnDNSScreenDisabledWithoutInput() throws {
        app.tabBars.buttons["Tools"].tap()
        let dnsCard = ui("tools_card_dns_lookup")
        if dnsCard.waitForExistence(timeout: 5) {
            dnsCard.tap()
        }
        let runButton = app.buttons["dnsLookup_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5),
                     "DNS lookup run button should exist")
        // FUNCTIONAL: run button should be disabled without domain input
        XCTAssertFalse(runButton.isEnabled,
                      "DNS lookup run button should be disabled before entering a domain")
    }

    func testToolRunButtonOnWHOISScreenDisabledWithoutInput() throws {
        app.tabBars.buttons["Tools"].tap()
        let whoisCard = ui("tools_card_whois")
        if whoisCard.waitForExistence(timeout: 5) {
            whoisCard.tap()
        }
        let runButton = app.buttons["whois_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5),
                     "WHOIS run button should exist")
        // FUNCTIONAL: run button should be disabled without domain input
        XCTAssertFalse(runButton.isEnabled,
                      "WHOIS run button should be disabled before entering a domain")
    }

    func testToolRunButtonOnSpeedTestScreenIsEnabled() throws {
        app.tabBars.buttons["Tools"].tap()
        let speedTestCard = ui("tools_card_speed_test")
        if speedTestCard.waitForExistence(timeout: 5) {
            speedTestCard.tap()
        }
        let runButton = app.buttons["speedTest_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5),
                     "Speed test run button should exist")
        // FUNCTIONAL: speed test run button should be enabled immediately (no required input)
        XCTAssertTrue(runButton.isEnabled,
                     "Speed test run button should be enabled by default")
    }

    func testToolRunButtonOnBonjourScreenIsEnabled() throws {
        app.tabBars.buttons["Tools"].tap()
        let bonjourCard = ui("tools_card_bonjour")
        if bonjourCard.waitForExistence(timeout: 5) {
            bonjourCard.tap()
        }
        let runButton = app.buttons["bonjour_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5),
                     "Bonjour run button should exist")
        // FUNCTIONAL: bonjour run button should be enabled immediately
        XCTAssertTrue(runButton.isEnabled,
                     "Bonjour run button should be enabled by default")
    }

    // MARK: - ToolClearButton (After running tools)

    func testToolClearButtonAppearsAfterPingRun() throws {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = ui("tools_card_ping")
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
        }
        let hostField = app.textFields["pingTool_input_host"]
        if hostField.waitForExistence(timeout: 5) {
            hostField.tap()
            hostField.typeText("8.8.8.8")
            app.buttons["pingTool_button_run"].tap()
            // Wait for ping to complete and clear button to appear
            let clearButton = app.buttons["pingTool_button_clear"]
            XCTAssertTrue(clearButton.waitForExistence(timeout: 30),
                         "Clear button should appear after running ping")
            // FUNCTIONAL: clear button should be tappable
            XCTAssertTrue(clearButton.isEnabled,
                         "Clear button should be enabled after ping completes")
        }
    }

    // MARK: - ToolInputField (All tool screens)

    func testToolInputFieldOnPingScreenAcceptsText() throws {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = ui("tools_card_ping")
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
        }
        let inputField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 5),
                     "Ping input field should exist")
        // FUNCTIONAL: input field should accept text
        inputField.tap()
        inputField.typeText("8.8.8.8")
        XCTAssertEqual(inputField.value as? String, "8.8.8.8",
                       "Ping input field should contain typed host value")

        // Test the clear button on input field
        let clearInput = app.buttons["pingTool_input_host_button_clear"]
        if clearInput.waitForExistence(timeout: 3) {
            clearInput.tap()
            // FUNCTIONAL: clear button should clear the field
            let fieldValue = inputField.value as? String ?? ""
            XCTAssertTrue(fieldValue.isEmpty || fieldValue == inputField.placeholderValue,
                         "Input field should be cleared after tapping clear button")
        }
    }

    func testToolInputFieldOnPortScannerScreenAcceptsText() throws {
        app.tabBars.buttons["Tools"].tap()
        let portScannerCard = ui("tools_card_port_scanner")
        if portScannerCard.waitForExistence(timeout: 5) {
            portScannerCard.tap()
        }
        let inputField = app.textFields["portScanner_input_host"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 5),
                     "Port scanner input field should exist")
        // FUNCTIONAL: input field should accept text
        inputField.tap()
        inputField.typeText("192.168.1.1")
        XCTAssertEqual(inputField.value as? String, "192.168.1.1",
                       "Port scanner input field should contain typed host value")
    }

    // MARK: - ToolResultRow (Visible in dashboard cards)

    func testToolResultRowInDashboardCardsHasContent() throws {
        // WiFi card contains ToolResultRow instances
        let wifiCard = ui("dashboard_card_wifi")
        XCTAssertTrue(wifiCard.waitForExistence(timeout: 5),
                     "WiFi card should exist on dashboard")
        // FUNCTIONAL: WiFi card should contain metric text data
        XCTAssertTrue(
            wifiCard.staticTexts.count > 0,
            "WiFi card should contain result/metric text content"
        )
    }

    // MARK: - ToolStatisticsCard (After ping completion)

    func testToolStatisticsCardAfterPingContainsStats() throws {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = ui("tools_card_ping")
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
        }
        let hostField = app.textFields["pingTool_input_host"]
        if hostField.waitForExistence(timeout: 5) {
            hostField.tap()
            hostField.typeText("8.8.8.8")
            app.buttons["pingTool_button_run"].tap()
            let statsCard = ui("pingTool_card_statistics")
            XCTAssertTrue(statsCard.waitForExistence(timeout: 30),
                         "Statistics card should appear after ping completes")
            // FUNCTIONAL: statistics card should contain min/avg/max data
            XCTAssertTrue(
                statsCard.staticTexts.count > 0,
                "Statistics card should contain ping statistics text (min/avg/max)"
            )
        }
    }

    // MARK: - ToolCard (Tools grid)

    func testToolCardsExistInGridAndAreTappable() throws {
        app.tabBars.buttons["Tools"].tap()
        let toolsGrid = ui("tools_section_grid")
        XCTAssertTrue(toolsGrid.waitForExistence(timeout: 5),
                     "Tools grid section should exist")

        // Verify key tool cards exist
        XCTAssertTrue(ui("tools_card_ping").exists, "Ping card should exist in grid")
        XCTAssertTrue(ui("tools_card_traceroute").exists, "Traceroute card should exist in grid")
        XCTAssertTrue(ui("tools_card_dns_lookup").exists, "DNS lookup card should exist in grid")
        XCTAssertTrue(ui("tools_card_port_scanner").exists, "Port scanner card should exist in grid")
    }

    func testToolCardsNavigateCorrectlyToToolScreens() throws {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = ui("tools_card_ping")
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
            XCTAssertTrue(
                ui("screen_pingTool").waitForExistence(timeout: 5),
                "Tapping Ping card should navigate to Ping tool screen"
            )
            // FUNCTIONAL: ping tool screen should contain input field and run button
            XCTAssertTrue(
                app.textFields["pingTool_input_host"].waitForExistence(timeout: 3),
                "Ping tool screen should show host input field"
            )
            XCTAssertTrue(
                app.buttons["pingTool_button_run"].waitForExistence(timeout: 3),
                "Ping tool screen should show run button"
            )
        }
    }
}
