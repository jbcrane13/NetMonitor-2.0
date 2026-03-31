import XCTest

/// Interaction-outcome tests for every macOS tool sheet.
///
/// Each test opens a tool, exercises its primary interaction (type input,
/// tap run/lookup/send, observe running/result state, stop/clear), and
/// verifies the outcome transitions.  Modelled after the iOS
/// ``ToolOutcomeUITests`` but adapted for macOS controls (popUpButtons,
/// modal sheets, etc.).
@MainActor
final class MacOSToolOutcomeUITests: MacOSUITestCase {

    // MARK: - Ping

    func testPingValidationRunAndCloseOutcome() {
        openTool(cardID: "tools_card_ping", sheetElement: "ping_textfield_host")

        let runButton = requireExists(
            app.buttons["ping_button_run"],
            message: "Ping run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Run should be disabled with empty host")

        clearAndTypeText("127.0.0.1", into: app.textFields["ping_textfield_host"])
        XCTAssertTrue(runButton.isEnabled, "Run should be enabled after entering host")

        runButton.tap()

        // The button remains visible; its label changes to "Stop" while running.
        XCTAssertTrue(
            waitForEither(
                [app.buttons["ping_button_run"], ui("ping_results")],
                timeout: 10
            ),
            "Ping should transition to running state or show results"
        )

        // Tap again to stop if still running.
        if runButton.exists && runButton.isEnabled {
            runButton.tap()
        }

        closeTool(closeButtonID: "ping_button_close", cardID: "tools_card_ping")
    }

    func testPingCountPickerIsInteractive() {
        openTool(cardID: "tools_card_ping", sheetElement: "ping_textfield_host")

        let countPicker = requireExists(
            app.popUpButtons["ping_picker_count"],
            message: "Ping count picker should exist"
        )
        XCTAssertTrue(countPicker.isEnabled, "Count picker should be interactive")

        closeTool(closeButtonID: "ping_button_close", cardID: "tools_card_ping")
    }

    // MARK: - Traceroute

    func testTracerouteValidationRunAndCloseOutcome() {
        openTool(cardID: "tools_card_traceroute", sheetElement: "traceroute_textfield_host")

        let runButton = requireExists(
            app.buttons["traceroute_button_run"],
            message: "Traceroute run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Run should be disabled with empty host")

        clearAndTypeText("1.1.1.1", into: app.textFields["traceroute_textfield_host"])
        XCTAssertTrue(runButton.isEnabled, "Run should be enabled after entering host")

        runButton.tap()
        XCTAssertTrue(
            waitForEither(
                [app.buttons["traceroute_button_run"], ui("traceroute_results")],
                timeout: 15
            ),
            "Traceroute should transition to running state"
        )

        if runButton.exists && runButton.isEnabled {
            runButton.tap()
        }

        closeTool(closeButtonID: "traceroute_button_close", cardID: "tools_card_traceroute")
    }

    func testTracerouteHopsPickerIsInteractive() {
        openTool(cardID: "tools_card_traceroute", sheetElement: "traceroute_textfield_host")

        let hopsPicker = requireExists(
            app.popUpButtons["traceroute_picker_hops"],
            message: "Traceroute hops picker should exist"
        )
        XCTAssertTrue(hopsPicker.isEnabled, "Hops picker should be interactive")

        closeTool(closeButtonID: "traceroute_button_close", cardID: "tools_card_traceroute")
    }

    // MARK: - Port Scanner

    func testPortScannerValidationRunAndCloseOutcome() {
        openTool(cardID: "tools_card_port_scanner", sheetElement: "portScan_textfield_host")

        let scanButton = requireExists(
            app.buttons["portScan_button_scan"],
            message: "Port scanner scan button should exist"
        )
        XCTAssertFalse(scanButton.isEnabled, "Scan should be disabled with empty host")

        clearAndTypeText("127.0.0.1", into: app.textFields["portScan_textfield_host"])
        XCTAssertTrue(scanButton.isEnabled, "Scan should be enabled after entering host")

        scanButton.tap()
        XCTAssertTrue(
            waitForEither(
                [app.buttons["portScan_button_scan"], ui("portScan_results")],
                timeout: 10
            ),
            "Port scanner should enter running state"
        )

        if scanButton.exists && scanButton.isEnabled {
            scanButton.tap()
        }

        closeTool(closeButtonID: "portScan_button_close", cardID: "tools_card_port_scanner")
    }

    func testPortScannerPresetPickerIsInteractive() {
        openTool(cardID: "tools_card_port_scanner", sheetElement: "portScan_textfield_host")

        let presetPicker = requireExists(
            app.popUpButtons["portScan_picker_preset"],
            message: "Port scanner preset picker should exist"
        )
        XCTAssertTrue(presetPicker.isEnabled, "Preset picker should be interactive")

        closeTool(closeButtonID: "portScan_button_close", cardID: "tools_card_port_scanner")
    }

    // MARK: - DNS Lookup

    func testDNSLookupValidationRunClearAndCloseOutcome() {
        openTool(cardID: "tools_card_dns_lookup", sheetElement: "dns_textfield_hostname")

        let lookupButton = requireExists(
            app.buttons["dns_button_lookup"],
            message: "DNS lookup button should exist"
        )
        XCTAssertFalse(lookupButton.isEnabled, "Lookup should be disabled with empty hostname")

        clearAndTypeText("example.com", into: app.textFields["dns_textfield_hostname"])
        XCTAssertTrue(lookupButton.isEnabled, "Lookup should be enabled after entering hostname")

        lookupButton.tap()

        let clearButton = app.buttons["dns_button_clear"]
        XCTAssertTrue(
            waitForEither(
                [clearButton, ui("dns_results"), ui("dns_error")],
                timeout: 20
            ),
            "DNS lookup should produce results, clear button, or error"
        )

        if clearButton.exists {
            clearButton.tap()
            XCTAssertTrue(
                waitForDisappearance(clearButton, timeout: 5),
                "Clear button should disappear after clearing DNS results"
            )
        }

        closeTool(closeButtonID: "dns_button_close", cardID: "tools_card_dns_lookup")
    }

    func testDNSLookupRecordTypePickerIsInteractive() {
        openTool(cardID: "tools_card_dns_lookup", sheetElement: "dns_textfield_hostname")

        let typePicker = requireExists(
            app.popUpButtons["dns_picker_type"],
            message: "DNS record type picker should exist"
        )
        XCTAssertTrue(typePicker.isEnabled, "Record type picker should be interactive")

        closeTool(closeButtonID: "dns_button_close", cardID: "tools_card_dns_lookup")
    }

    // MARK: - WHOIS

    func testWHOISValidationRunClearAndCloseOutcome() {
        openTool(cardID: "tools_card_whois", sheetElement: "whois_textfield_domain")

        let lookupButton = requireExists(
            app.buttons["whois_button_lookup"],
            message: "WHOIS lookup button should exist"
        )
        XCTAssertFalse(lookupButton.isEnabled, "Lookup should be disabled with empty domain")

        clearAndTypeText("example.com", into: app.textFields["whois_textfield_domain"])
        XCTAssertTrue(lookupButton.isEnabled, "Lookup should be enabled after entering domain")

        lookupButton.tap()

        let clearButton = app.buttons["whois_button_clear"]
        let viewModePicker = app.segmentedControls["whois_picker_viewmode"]
        XCTAssertTrue(
            waitForEither(
                [clearButton, viewModePicker, ui("whois_results"), ui("whois_error")],
                timeout: 35
            ),
            "WHOIS lookup should produce results or show error"
        )

        if clearButton.exists {
            clearButton.tap()
            XCTAssertTrue(
                waitForDisappearance(clearButton, timeout: 5),
                "Clear button should disappear after clearing WHOIS results"
            )
        }

        closeTool(closeButtonID: "whois_button_close", cardID: "tools_card_whois")
    }

    // MARK: - Speed Test

    func testSpeedTestStartStopAndCloseOutcome() {
        openTool(cardID: "tools_card_speed_test", sheetElement: "speedTest_button_start")

        let startButton = requireExists(
            app.buttons["speedTest_button_start"],
            message: "Speed test start button should exist"
        )
        XCTAssertTrue(startButton.isEnabled, "Start button should be enabled")

        requireExists(
            app.segmentedControls["speedTest_picker_duration"],
            message: "Duration picker should exist"
        )

        startButton.tap()

        let stopButton = app.buttons["speedTest_button_stop"]
        XCTAssertTrue(
            stopButton.waitForExistence(timeout: 8),
            "Stop button should appear after starting speed test"
        )

        stopButton.tap()

        XCTAssertTrue(
            app.buttons["speedTest_button_start"].waitForExistence(timeout: 8),
            "Start button should reappear after stopping speed test"
        )

        closeTool(closeButtonID: "speedTest_button_close", cardID: "tools_card_speed_test")
    }

    func testSpeedTestDurationPickerSegments() {
        openTool(cardID: "tools_card_speed_test", sheetElement: "speedTest_button_start")

        let picker = requireExists(
            app.segmentedControls["speedTest_picker_duration"],
            message: "Duration picker should exist"
        )
        XCTAssertEqual(picker.buttons.count, 3, "Duration picker should have 3 segments (5s, 10s, 30s)")

        closeTool(closeButtonID: "speedTest_button_close", cardID: "tools_card_speed_test")
    }

    // MARK: - Wake on LAN

    func testWakeOnLANValidationAndSendOutcome() {
        openTool(cardID: "tools_card_wake_on_lan", sheetElement: "wol_textfield_mac")

        let sendButton = requireExists(
            app.buttons["wol_button_send"],
            message: "WoL send button should exist"
        )
        XCTAssertFalse(sendButton.isEnabled, "Send should be disabled with empty MAC")

        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: app.textFields["wol_textfield_mac"])
        XCTAssertTrue(sendButton.isEnabled, "Send should be enabled for valid MAC")

        sendButton.tap()

        // After sending, the send button should remain visible (success/failure shown inline).
        requireExists(sendButton, timeout: 10,
                      message: "Send button should remain visible after sending WoL packet")

        closeTool(closeButtonID: "wol_button_close", cardID: "tools_card_wake_on_lan")
    }

    func testWakeOnLANBroadcastDefaultAndDevicePicker() {
        openTool(cardID: "tools_card_wake_on_lan", sheetElement: "wol_textfield_mac")

        let broadcastField = requireExists(
            app.textFields["wol_textfield_broadcast"],
            message: "Broadcast field should exist"
        )
        XCTAssertEqual(
            broadcastField.value as? String, "255.255.255.255",
            "Default broadcast address should be 255.255.255.255"
        )

        let devicePicker = requireExists(
            app.popUpButtons["wol_picker_device"],
            message: "Device picker should exist"
        )
        XCTAssertTrue(devicePicker.isEnabled, "Device picker should be interactive")

        closeTool(closeButtonID: "wol_button_close", cardID: "tools_card_wake_on_lan")
    }

    // MARK: - Bonjour Browser

    func testBonjourBrowserRefreshAndCloseOutcome() {
        openTool(cardID: "tools_card_bonjour_browser", sheetElement: "bonjour_button_close")

        let refreshButton = requireExists(
            app.buttons["bonjour_button_refresh"],
            message: "Bonjour refresh button should exist"
        )

        // Bonjour auto-scans on open; refresh should be enabled once scanning settles.
        XCTAssertTrue(
            refreshButton.waitForExistence(timeout: 10),
            "Refresh button should become available"
        )
        refreshButton.tap()

        // After refresh, the close button should still be accessible.
        requireExists(
            app.buttons["bonjour_button_close"],
            message: "Close button should remain after refresh"
        )

        closeTool(closeButtonID: "bonjour_button_close", cardID: "tools_card_bonjour_browser")
    }
}
