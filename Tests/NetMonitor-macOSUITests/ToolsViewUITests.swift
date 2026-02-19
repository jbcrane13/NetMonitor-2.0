import XCTest

@MainActor
final class ToolsViewUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Tools
        let sidebar = app.staticTexts["sidebar_tools"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Detail Pane

    func testToolsDetailExists() {
        XCTAssertTrue(app.otherElements["detail_tools"].waitForExistence(timeout: 3))
    }

    // MARK: - Tool Cards Existence

    func testPingCardExists() {
        XCTAssertTrue(app.otherElements["tools_card_ping"].waitForExistence(timeout: 3))
    }

    func testTracerouteCardExists() {
        XCTAssertTrue(app.otherElements["tools_card_traceroute"].waitForExistence(timeout: 3))
    }

    func testPortScannerCardExists() {
        XCTAssertTrue(app.otherElements["tools_card_port_scanner"].waitForExistence(timeout: 3))
    }

    func testDNSLookupCardExists() {
        XCTAssertTrue(app.otherElements["tools_card_dns_lookup"].waitForExistence(timeout: 3))
    }

    func testWHOISCardExists() {
        XCTAssertTrue(app.otherElements["tools_card_whois"].waitForExistence(timeout: 3))
    }

    func testSpeedTestCardExists() {
        XCTAssertTrue(app.otherElements["tools_card_speed_test"].waitForExistence(timeout: 3))
    }

    func testBonjourBrowserCardExists() {
        XCTAssertTrue(app.otherElements["tools_card_bonjour_browser"].waitForExistence(timeout: 3))
    }

    func testWakeOnLanCardExists() {
        XCTAssertTrue(app.otherElements["tools_card_wake_on_lan"].waitForExistence(timeout: 3))
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
            XCTAssertTrue(app.otherElements[cardID].waitForExistence(timeout: 3),
                          "\(cardID) should exist")
        }
    }

    // MARK: - Tool Card Opens Sheet

    func testPingCardOpensSheet() {
        app.otherElements["tools_card_ping"].tap()
        XCTAssertTrue(app.textFields["ping_textfield_host"].waitForExistence(timeout: 3))
    }

    func testTracerouteCardOpensSheet() {
        app.otherElements["tools_card_traceroute"].tap()
        XCTAssertTrue(app.textFields["traceroute_textfield_host"].waitForExistence(timeout: 3))
    }

    func testDNSLookupCardOpensSheet() {
        app.otherElements["tools_card_dns_lookup"].tap()
        XCTAssertTrue(app.textFields["dns_textfield_hostname"].waitForExistence(timeout: 3))
    }

    func testWHOISCardOpensSheet() {
        app.otherElements["tools_card_whois"].tap()
        XCTAssertTrue(app.textFields["whois_textfield_domain"].waitForExistence(timeout: 3))
    }

    func testSpeedTestCardOpensSheet() {
        app.otherElements["tools_card_speed_test"].tap()
        XCTAssertTrue(app.buttons["speedtest_button_start"].waitForExistence(timeout: 3))
    }

    func testPortScannerCardOpensSheet() {
        app.otherElements["tools_card_port_scanner"].tap()
        XCTAssertTrue(app.textFields["portscan_textfield_host"].waitForExistence(timeout: 3))
    }

    func testBonjourBrowserCardOpensSheet() {
        app.otherElements["tools_card_bonjour_browser"].tap()
        XCTAssertTrue(app.buttons["bonjour_button_close"].waitForExistence(timeout: 3))
    }

    func testWakeOnLanCardOpensSheet() {
        app.otherElements["tools_card_wake_on_lan"].tap()
        XCTAssertTrue(app.textFields["wol_textfield_mac"].waitForExistence(timeout: 3))
    }

    // MARK: - Open and Close Tool

    func testOpenAndClosePingTool() {
        app.otherElements["tools_card_ping"].tap()
        XCTAssertTrue(app.buttons["ping_button_close"].waitForExistence(timeout: 3))
        app.buttons["ping_button_close"].tap()
        XCTAssertTrue(app.otherElements["tools_card_ping"].waitForExistence(timeout: 3))
    }
}
