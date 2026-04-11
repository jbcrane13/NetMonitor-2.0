import XCTest

@MainActor
final class ToolOutcomeUITests: IOSUITestCase {
    func testSetTargetPrefillsTargetAwareToolInputs() {
        let target = "9.9.9.9"
        openToolsRoot()

        let setTargetQuickAction = requireExists(
            app.buttons["quickAction_button_setTarget"],
            message: "Set Target quick action should exist"
        )
        setTargetQuickAction.tap()

        let addressField = app.textFields["setTarget_textfield_address"]
        clearAndTypeText(target, into: addressField)
        requireExists(
            app.buttons["setTarget_button_set"],
            message: "Set button should appear after entering a target"
        ).tap()
        XCTAssertTrue(
            waitForDisappearance(addressField, timeout: 3),
            "Set Target sheet should dismiss after saving"
        )

        XCTAssertTrue(
            app.buttons["quickAction_button_setTarget"].label.contains(target),
            "Set Target quick action should show the selected target"
        )

        assertToolInputPrefill(cardID: "tools_card_ping", screenID: "screen_pingTool", inputID: "pingTool_input_host", expected: target)
        assertToolInputPrefill(cardID: "tools_card_traceroute", screenID: "screen_tracerouteTool", inputID: "tracerouteTool_input_host", expected: target)
        assertToolInputPrefill(cardID: "tools_card_dns_lookup", screenID: "screen_dnsLookupTool", inputID: "dnsLookup_input_domain", expected: target)
        assertToolInputPrefill(cardID: "tools_card_port_scanner", screenID: "screen_portScannerTool", inputID: "portScanner_input_host", expected: target)
        assertToolInputPrefill(cardID: "tools_card_whois", screenID: "screen_whoisTool", inputID: "whois_input_domain", expected: target)
    }

    func testPingValidationRunStopAndClearOutcome() {
        openTool(cardID: "tools_card_ping", screenID: "screen_pingTool")

        let runButton = requireExists(
            app.buttons["pingTool_button_run"],
            message: "Ping run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Run should be disabled with empty host")

        clearAndTypeText("127.0.0.1", into: app.textFields["pingTool_input_host"])
        XCTAssertTrue(runButton.isEnabled, "Run should be enabled after entering host")

        runButton.tap()
        XCTAssertTrue(
            waitForEither(
                [
                    app.buttons["Stop Ping"],
                    app.otherElements["pingTool_section_results"]
                ],
                timeout: 15
            ),
            "Ping should transition to running or show results after tapping Run"
        )

        if app.buttons["Stop Ping"].exists {
            runButton.tap()
        }
        requireExists(runButton, message: "Ping run button should still be visible after second tap")

        let clearButton = requireExists(
            app.buttons["pingTool_button_clear"],
            timeout: 15,
            message: "Clear button should appear after ping produces results"
        )
        clearButton.tap()
        XCTAssertTrue(
            waitForDisappearance(app.otherElements["pingTool_section_results"], timeout: 5),
            "Results section should be removed after Clear"
        )
    }

    func testTracerouteValidationRunStopAndClearOutcome() {
        openTool(cardID: "tools_card_traceroute", screenID: "screen_tracerouteTool")

        let runButton = requireExists(
            app.buttons["tracerouteTool_button_run"],
            message: "Traceroute run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Run should be disabled with empty host")

        clearAndTypeText("1.1.1.1", into: app.textFields["tracerouteTool_input_host"])
        XCTAssertTrue(runButton.isEnabled, "Run should be enabled after entering host")

        runButton.tap()
        XCTAssertTrue(
            waitForEither(
                [
                    app.buttons["Stop Trace"],
                    app.otherElements["tracerouteTool_section_hops"]
                ],
                timeout: 20
            ),
            "Traceroute should transition to running or show hop results"
        )

        if app.buttons["Stop Trace"].exists {
            runButton.tap()
        }

        if app.otherElements["tracerouteTool_section_hops"].exists {
            let clearButton = requireExists(
                app.buttons["tracerouteTool_button_clear"],
                timeout: 10,
                message: "Clear button should appear once traceroute has results"
            )
            clearButton.tap()
            XCTAssertTrue(
                waitForDisappearance(app.otherElements["tracerouteTool_section_hops"], timeout: 5),
                "Traceroute hops should be removed after Clear"
            )
        }
    }

    func testPortScannerValidationAndRunStopOutcome() {
        openTool(cardID: "tools_card_port_scanner", screenID: "screen_portScannerTool")

        let runButton = requireExists(
            app.buttons["portScanner_button_run"],
            message: "Port scanner run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Run should be disabled with empty host")

        clearAndTypeText("127.0.0.1", into: app.textFields["portScanner_input_host"])
        XCTAssertTrue(runButton.isEnabled, "Run should be enabled after entering host")

        runButton.tap()
        XCTAssertTrue(
            waitForEither(
                [
                    app.otherElements["portScanner_progress"],
                    app.buttons["Stop Scan"]
                ],
                timeout: 10
            ),
            "Port scanner should enter running state and show progress/stop control"
        )

        if app.buttons["Stop Scan"].exists {
            runButton.tap()
        }
        requireExists(runButton, message: "Port scanner run button should remain visible after second tap")
    }

    func testDNSLookupValidationAndOutcomeTransition() {
        openTool(cardID: "tools_card_dns_lookup", screenID: "screen_dnsLookupTool")

        let runButton = requireExists(
            app.buttons["dnsLookup_button_run"],
            message: "DNS run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Run should be disabled with empty domain")

        clearAndTypeText("example.com", into: app.textFields["dnsLookup_input_domain"])
        XCTAssertTrue(runButton.isEnabled, "Run should be enabled after entering a domain")

        runButton.tap()
        XCTAssertTrue(
            waitForEither(
                [
                    app.buttons["Looking up..."],
                    app.otherElements["dnsLookup_label_error"],
                    app.otherElements["dnsLookup_section_queryInfo"],
                    app.buttons["dnsLookup_button_clear"]
                ],
                timeout: 20
            ),
            "DNS lookup should enter loading state or produce a visible success/error outcome"
        )
    }

    func testWHOISValidationAndOutcomeTransition() {
        openTool(cardID: "tools_card_whois", screenID: "screen_whoisTool")

        let runButton = requireExists(
            app.buttons["whois_button_run"],
            message: "WHOIS run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Run should be disabled with empty domain")

        clearAndTypeText("example.com", into: app.textFields["whois_input_domain"])
        XCTAssertTrue(runButton.isEnabled, "Run should be enabled after entering a domain")

        runButton.tap()
        XCTAssertTrue(
            waitForEither(
                [
                    app.buttons["Looking up..."],
                    app.otherElements["whois_label_error"],
                    app.otherElements["whois_section_domainInfo"],
                    app.buttons["whois_button_clear"]
                ],
                timeout: 20
            ),
            "WHOIS should enter loading state or produce a visible success/error outcome"
        )
    }

    func testWakeOnLANValidationAndSendOutcome() {
        openTool(cardID: "tools_card_wake_on_lan", screenID: "screen_wolTool")

        let sendButton = requireExists(
            app.buttons["wol_button_send"],
            message: "Wake-on-LAN send button should exist"
        )
        XCTAssertFalse(sendButton.isEnabled, "Send should be disabled with empty MAC")

        clearAndTypeText("1234", into: app.textFields["wol_input_mac"])
        XCTAssertFalse(sendButton.isEnabled, "Send should remain disabled for invalid MAC format")
        requireExists(
            app.staticTexts["Invalid MAC address format"],
            message: "Invalid MAC helper text should be visible for malformed addresses"
        )

        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: app.textFields["wol_input_mac"])
        XCTAssertTrue(sendButton.isEnabled, "Send should be enabled for valid MAC format")
        requireExists(
            app.staticTexts["Valid MAC address"],
            message: "Valid MAC helper text should be visible for well-formed addresses"
        )

        sendButton.tap()
        XCTAssertTrue(
            waitForEither(
                [
                    app.buttons["Sending..."],
                    app.staticTexts["Wake packet sent!"],
                    app.staticTexts["Failed to send"]
                ],
                timeout: 8
            ),
            "Wake-on-LAN should show sending state or final success/failure message after sending"
        )
        requireExists(ui("screen_wolTool"), message: "Wake-on-LAN screen should remain visible after sending")
    }

    func testSpeedTestRunStopOutcome() {
        openTool(cardID: "tools_card_speed_test", screenID: "screen_speedTestTool")

        let runButton = requireExists(
            app.buttons["speedTest_button_run"],
            message: "Speed test run button should exist"
        )
        requireExists(
            app.segmentedControls["speedTest_picker_duration"],
            message: "Speed test duration picker should exist"
        )

        runButton.tap()
        XCTAssertTrue(
            waitForEither(
                [
                    app.buttons["Stop Test"],
                    app.staticTexts["Testing latency..."],
                    app.staticTexts["Testing download..."],
                    app.staticTexts["Testing upload..."]
                ],
                timeout: 8
            ),
            "Speed test should enter a running phase after tapping Start"
        )

        runButton.tap()
        requireExists(runButton, message: "Speed test run button should remain visible after stopping")
        requireExists(ui("speedTest_label_gauge"), message: "Speed test gauge should remain visible after running/stopping")
    }

    func testBonjourStartStopOutcome() {
        openTool(cardID: "tools_card_bonjour", screenID: "screen_bonjourTool")

        let runButton = requireExists(
            app.buttons["bonjour_button_run"],
            message: "Bonjour run button should exist"
        )
        runButton.tap()

        XCTAssertTrue(
            waitForEither(
                [
                    app.staticTexts["Discovering services..."],
                    app.otherElements["bonjour_section_services"],
                    app.otherElements["bonjour_label_noServices"]
                ],
                timeout: 10
            ),
            "Bonjour discovery should show visible discovery outcome after starting"
        )

        runButton.tap()
        requireExists(runButton, message: "Bonjour run button should remain visible after stopping")
    }

    func testWebBrowserValidationAndBookmarksVisible() {
        openTool(cardID: "tools_card_web_browser", screenID: "screen_webBrowser")

        let openButton = requireExists(
            app.buttons["webBrowser_button_open"],
            message: "Web browser open button should exist"
        )
        XCTAssertFalse(openButton.isEnabled, "Open button should be disabled when URL field is empty")

        requireExists(
            ui("webBrowser_section_bookmarks"),
            message: "Bookmarks section should be visible on web browser screen"
        )
        requireExists(
            ui("webBrowser_bookmark_router_admin"),
            message: "Router Admin bookmark should be visible on web browser screen"
        )

        clearAndTypeText("https://example.com", into: app.textFields["webBrowser_input_url"])
        XCTAssertTrue(openButton.isEnabled, "Open button should be enabled after entering URL")
    }

    private func openToolsRoot() {
        let toolsTab = requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist")
        toolsTab.tap()
        XCTAssertTrue(
            waitForEither(
                [
                    app.buttons["quickAction_button_setTarget"],
                    ui("tools_section_grid"),
                    ui("tools_card_ping")
                ],
                timeout: 8
            ),
            "Tools root content should be visible after selecting the Tools tab"
        )
    }

    private func openTool(cardID: String, screenID: String) {
        openToolsRoot()
        let card = ui(cardID)
        scrollToElement(card)
        requireExists(card, timeout: 8, message: "Tool card \(cardID) should exist")
        card.tap()
        requireExists(
            ui(screenID),
            timeout: 8,
            message: "Expected \(screenID) after opening \(cardID)"
        )
    }

    private func assertToolInputPrefill(cardID: String, screenID: String, inputID: String, expected: String) {
        openTool(cardID: cardID, screenID: screenID)
        let input = requireExists(
            app.textFields[inputID],
            timeout: 8,
            message: "Expected tool input \(inputID) for \(cardID)"
        )
        XCTAssertEqual(
            normalizedFieldValue(input),
            expected,
            "Input \(inputID) should be prefilled with selected target \(expected)"
        )
        navigateBackToTools()
    }

    private func navigateBackToTools() {
        let backButton = requireExists(
            app.navigationBars.buttons.firstMatch,
            message: "Back button should be visible to return to Tools"
        )
        backButton.tap()
        XCTAssertTrue(
            waitForEither(
                [
                    app.buttons["quickAction_button_setTarget"],
                    ui("tools_section_grid"),
                    ui("tools_card_ping")
                ],
                timeout: 8
            ),
            "Tools root content should be visible after navigating back"
        )
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func normalizedFieldValue(_ field: XCUIElement) -> String {
        let raw = String(describing: field.value as Any)
        return raw
            .replacingOccurrences(of: "Optional(\"", with: "")
            .replacingOccurrences(of: "\")", with: "")
            .replacingOccurrences(of: "Optional(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
