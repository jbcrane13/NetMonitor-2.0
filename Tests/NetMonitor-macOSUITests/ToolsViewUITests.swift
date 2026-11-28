import XCTest

@MainActor
final class ToolsViewUITests: MacOSUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        navigateToSidebar("tools")
    }

    // MARK: - Detail Pane

    func testToolsDetailExists() {
        requireExists(ui("contentView_nav_tools").firstMatch, timeout: 3,
                      message: "Tools detail pane should exist")
    }

    // MARK: - Tool Cards Existence

    func testPingCardExists() {
        requireExists(ui("tools_card_ping").firstMatch, timeout: 3,
                      message: "Ping card should exist")
    }

    func testTracerouteCardExists() {
        requireExists(ui("tools_card_traceroute").firstMatch, timeout: 3,
                      message: "Traceroute card should exist")
    }

    func testPortScannerCardExists() {
        requireExists(ui("tools_card_port_scanner").firstMatch, timeout: 3,
                      message: "Port scanner card should exist")
    }

    func testDNSLookupCardExists() {
        requireExists(ui("tools_card_dns_lookup").firstMatch, timeout: 3,
                      message: "DNS lookup card should exist")
    }

    func testWHOISCardExists() {
        requireExists(ui("tools_card_whois").firstMatch, timeout: 3,
                      message: "WHOIS card should exist")
    }

    func testSpeedTestCardExists() {
        requireExists(ui("tools_card_speed_test").firstMatch, timeout: 3,
                      message: "Speed test card should exist")
    }

    func testBonjourBrowserCardExists() {
        requireExists(ui("tools_card_bonjour_browser").firstMatch, timeout: 3,
                      message: "Bonjour browser card should exist")
    }

    func testWakeOnLanCardExists() {
        requireExists(ui("tools_card_wake_on_lan").firstMatch, timeout: 3,
                      message: "Wake on LAN card should exist")
    }

    // MARK: - All 8 Tool Cards Present

    func testAllEightToolCardsPresent() {
        let toolCards = [
            "tools_card_ping",
            "tools_card_traceroute",
            "tools_card_port_scanner",
            "tools_card_dns_lookup",
            "tools_card_whois",
            "tools_card_speed_test",
            "tools_card_bonjour_browser",
            "tools_card_wake_on_lan"
        ]

        for cardID in toolCards {
            requireExists(ui(cardID).firstMatch, timeout: 3,
                          message: "\(cardID) should exist")
        }
    }

    func testAllToolCardsAreVisible() {
        let toolCards = [
            "tools_card_ping",
            "tools_card_traceroute",
            "tools_card_port_scanner",
            "tools_card_dns_lookup",
            "tools_card_whois",
            "tools_card_speed_test",
            "tools_card_bonjour_browser",
            "tools_card_wake_on_lan"
        ]

        for cardID in toolCards {
            requireExists(ui(cardID).firstMatch, timeout: 5,
                          message: "\(cardID) should be visible in the tools grid")
        }
    }

    // MARK: - Tool Card Opens Sheet

    func testPingCardOpensSheet() {
        let card = requireExists(ui("tools_card_ping").firstMatch, timeout: 3,
                                 message: "Ping card should exist")
        card.click()
        requireExists(app.textFields["ping_textfield_host"], timeout: 5,
                      message: "Ping host field should appear after opening ping card")
        captureScreenshot(named: "ToolsView_PingSheet")
    }

    func testTracerouteCardOpensSheet() {
        let card = requireExists(ui("tools_card_traceroute").firstMatch, timeout: 3,
                                 message: "Traceroute card should exist")
        card.click()
        requireExists(app.textFields["traceroute_textfield_host"], timeout: 5,
                      message: "Traceroute host field should appear after opening traceroute card")
    }

    func testDNSLookupCardOpensSheet() {
        let card = requireExists(ui("tools_card_dns_lookup").firstMatch, timeout: 3,
                                 message: "DNS lookup card should exist")
        card.click()
        requireExists(app.textFields["dns_textfield_hostname"], timeout: 5,
                      message: "DNS hostname field should appear after opening DNS lookup card")
    }

    func testWHOISCardOpensSheet() {
        let card = requireExists(ui("tools_card_whois").firstMatch, timeout: 3,
                                 message: "WHOIS card should exist")
        card.click()
        requireExists(app.textFields["whois_textfield_domain"], timeout: 5,
                      message: "WHOIS domain field should appear after opening WHOIS card")
    }

    func testSpeedTestCardOpensSheet() {
        let card = requireExists(ui("tools_card_speed_test").firstMatch, timeout: 3,
                                 message: "Speed test card should exist")
        card.click()
        requireExists(app.buttons["speedTest_button_start"], timeout: 5,
                      message: "Speed test start button should appear after opening speed test card")
    }

    func testPortScannerCardOpensSheet() {
        let card = requireExists(ui("tools_card_port_scanner").firstMatch, timeout: 3,
                                 message: "Port scanner card should exist")
        card.click()
        requireExists(app.textFields["portScan_textfield_host"], timeout: 5,
                      message: "Port scanner host field should appear after opening port scanner card")
    }

    func testBonjourBrowserCardOpensSheet() {
        let card = requireExists(ui("tools_card_bonjour_browser").firstMatch, timeout: 3,
                                 message: "Bonjour browser card should exist")
        card.click()
        requireExists(app.buttons["bonjour_button_close"], timeout: 5,
                      message: "Bonjour close button should appear after opening bonjour browser card")
    }

    func testWakeOnLanCardOpensSheet() {
        let card = requireExists(ui("tools_card_wake_on_lan").firstMatch, timeout: 3,
                                 message: "Wake on LAN card should exist")
        card.click()
        requireExists(app.textFields["wol_textfield_mac"], timeout: 5,
                      message: "WoL MAC field should appear after opening wake on LAN card")
    }

    // MARK: - Open and Close Tool

    func testOpenAndClosePingTool() {
        let card = requireExists(ui("tools_card_ping").firstMatch, timeout: 3,
                                 message: "Ping card should exist")
        card.click()
        let closeButton = requireExists(app.buttons["ping_button_close"], timeout: 5,
                                        message: "Ping close button should appear")
        closeButton.click()
        XCTAssertTrue(waitForDisappearance(closeButton), "Sheet should close")
        requireExists(ui("tools_card_ping").firstMatch, timeout: 5,
                      message: "Ping card should reappear after closing sheet")
    }

    func testToolCardOpenAndCloseRoundTrip() {
        let tools: [(card: String, sheetElement: String, close: String)] = [
            ("tools_card_ping", "ping_textfield_host", "ping_button_close"),
            ("tools_card_traceroute", "traceroute_textfield_host", "traceroute_button_close"),
        ]

        for tool in tools {
            let card = requireExists(ui(tool.card).firstMatch, timeout: 5,
                                     message: "\(tool.card) should exist")
            card.click()

            requireExists(ui(tool.sheetElement), timeout: 5,
                          message: "\(tool.sheetElement) should appear after opening \(tool.card)")

            let closeButton = requireExists(app.buttons[tool.close], timeout: 3,
                                            message: "\(tool.close) should exist")
            closeButton.click()
            XCTAssertTrue(waitForDisappearance(closeButton), "Sheet should close")

            requireExists(card, timeout: 5,
                          message: "\(tool.card) should reappear after closing sheet")
        }
    }
}
