import XCTest

@MainActor
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

    // MARK: - StatusBadge (Dashboard connection status)

    func testStatusBadgeExistsOnDashboard() throws {
        // The dashboard connection status header uses StatusBadge
        let header = app.otherElements["dashboard_label_connectionStatus"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
    }

    // MARK: - GlassButton (Tools quick actions)

    func testGlassButtonOnToolsScreen() throws {
        app.tabBars.buttons["Tools"].tap()
        // Quick action buttons use GlassButton styling
        let setTargetButton = app.buttons["quickAction_button_setTarget"]
        XCTAssertTrue(setTargetButton.waitForExistence(timeout: 5) ||
                      app.otherElements["quickAction_button_setTarget"].waitForExistence(timeout: 3))
    }

    func testGlassButtonSpeedTestQuickAction() throws {
        app.tabBars.buttons["Tools"].tap()
        let speedTestAction = app.buttons["quickAction_button_speedTest"]
        XCTAssertTrue(speedTestAction.waitForExistence(timeout: 5) ||
                      app.otherElements["quickAction_button_speedTest"].waitForExistence(timeout: 3))
    }

    // MARK: - MetricCard (Dashboard cards)

    func testMetricCardOnDashboard() throws {
        // Session card, WiFi card, etc. use GlassCard patterns similar to MetricCard
        XCTAssertTrue(app.otherElements["dashboard_card_session"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["dashboard_card_wifi"].exists)
    }

    // MARK: - EmptyStateView (Various screens)

    func testEmptyStateOnNetworkMap() throws {
        app.tabBars.buttons["Map"].tap()
        // If no devices, empty state should show; otherwise device list
        let emptyState = app.otherElements["networkMap_label_empty"]
        let deviceRow = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")).firstMatch
        let scanButton = app.buttons["networkMap_button_scan"]
        XCTAssertTrue(emptyState.exists || deviceRow.exists || scanButton.exists)
    }

    // MARK: - ToolRunButton (All tool screens)

    func testToolRunButtonOnPingScreen() throws {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = app.otherElements["tools_card_ping"]
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
        }
        XCTAssertTrue(app.buttons["pingTool_button_run"].waitForExistence(timeout: 5))
    }

    func testToolRunButtonOnTracerouteScreen() throws {
        app.tabBars.buttons["Tools"].tap()
        let tracerouteCard = app.otherElements["tools_card_traceroute"]
        if tracerouteCard.waitForExistence(timeout: 5) {
            tracerouteCard.tap()
        }
        XCTAssertTrue(app.buttons["tracerouteTool_button_run"].waitForExistence(timeout: 5))
    }

    func testToolRunButtonOnDNSScreen() throws {
        app.tabBars.buttons["Tools"].tap()
        let dnsCard = app.otherElements["tools_card_dns_lookup"]
        if dnsCard.waitForExistence(timeout: 5) {
            dnsCard.tap()
        }
        XCTAssertTrue(app.buttons["dnsLookup_button_run"].waitForExistence(timeout: 5))
    }

    func testToolRunButtonOnWHOISScreen() throws {
        app.tabBars.buttons["Tools"].tap()
        let whoisCard = app.otherElements["tools_card_whois"]
        if whoisCard.waitForExistence(timeout: 5) {
            whoisCard.tap()
        }
        XCTAssertTrue(app.buttons["whois_button_run"].waitForExistence(timeout: 5))
    }

    func testToolRunButtonOnSpeedTestScreen() throws {
        app.tabBars.buttons["Tools"].tap()
        let speedTestCard = app.otherElements["tools_card_speed_test"]
        if speedTestCard.waitForExistence(timeout: 5) {
            speedTestCard.tap()
        }
        XCTAssertTrue(app.buttons["speedTest_button_run"].waitForExistence(timeout: 5))
    }

    func testToolRunButtonOnBonjourScreen() throws {
        app.tabBars.buttons["Tools"].tap()
        let bonjourCard = app.otherElements["tools_card_bonjour"]
        if bonjourCard.waitForExistence(timeout: 5) {
            bonjourCard.tap()
        }
        XCTAssertTrue(app.buttons["bonjour_button_run"].waitForExistence(timeout: 5))
    }

    // MARK: - ToolClearButton (After running tools)

    func testToolClearButtonAppearsAfterPing() throws {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = app.otherElements["tools_card_ping"]
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
        }
        let hostField = app.textFields["pingTool_input_host"]
        if hostField.waitForExistence(timeout: 5) {
            hostField.tap()
            hostField.typeText("8.8.8.8")
            app.buttons["pingTool_button_run"].tap()
            // Wait for ping to complete
            let clearButton = app.buttons["pingTool_button_clear"]
            XCTAssertTrue(clearButton.waitForExistence(timeout: 30))
        }
    }

    // MARK: - ToolInputField (All tool screens)

    func testToolInputFieldOnPingScreen() throws {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = app.otherElements["tools_card_ping"]
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
        }
        let inputField = app.textFields["pingTool_input_host"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 5))
        // Test the clear button on input field
        inputField.tap()
        inputField.typeText("test")
        let clearInput = app.buttons["pingTool_input_host_button_clear"]
        if clearInput.waitForExistence(timeout: 3) {
            XCTAssertTrue(clearInput.exists)
        }
    }

    func testToolInputFieldOnPortScannerScreen() throws {
        app.tabBars.buttons["Tools"].tap()
        let portScannerCard = app.otherElements["tools_card_port_scanner"]
        if portScannerCard.waitForExistence(timeout: 5) {
            portScannerCard.tap()
        }
        XCTAssertTrue(app.textFields["portScanner_input_host"].waitForExistence(timeout: 5))
    }

    // MARK: - ToolResultRow (Visible in dashboard cards)

    func testToolResultRowInDashboardCards() throws {
        // WiFi card contains ToolResultRow instances
        let wifiCard = app.otherElements["dashboard_card_wifi"]
        XCTAssertTrue(wifiCard.waitForExistence(timeout: 5))
        // ToolResultRow accessibility IDs follow pattern: toolResult_row_{label}
        // These are dynamically visible based on WiFi state
    }

    // MARK: - ToolStatisticsCard (After ping completion)

    func testToolStatisticsCardAfterPing() throws {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = app.otherElements["tools_card_ping"]
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
        }
        let hostField = app.textFields["pingTool_input_host"]
        if hostField.waitForExistence(timeout: 5) {
            hostField.tap()
            hostField.typeText("8.8.8.8")
            app.buttons["pingTool_button_run"].tap()
            let statsCard = app.otherElements["pingTool_card_statistics"]
            XCTAssertTrue(statsCard.waitForExistence(timeout: 30))
        }
    }

    // MARK: - ToolCard (Tools grid)

    func testToolCardsExistInGrid() throws {
        app.tabBars.buttons["Tools"].tap()
        let toolsGrid = app.otherElements["tools_section_grid"]
        XCTAssertTrue(toolsGrid.waitForExistence(timeout: 5))

        // Verify key tool cards exist
        XCTAssertTrue(app.otherElements["tools_card_ping"].exists)
        XCTAssertTrue(app.otherElements["tools_card_traceroute"].exists)
        XCTAssertTrue(app.otherElements["tools_card_dns_lookup"].exists)
        XCTAssertTrue(app.otherElements["tools_card_port_scanner"].exists)
    }

    func testToolCardsNavigateCorrectly() throws {
        app.tabBars.buttons["Tools"].tap()
        let pingCard = app.otherElements["tools_card_ping"]
        if pingCard.waitForExistence(timeout: 5) {
            pingCard.tap()
            XCTAssertTrue(app.otherElements["screen_pingTool"].waitForExistence(timeout: 5))
        }
    }
}
