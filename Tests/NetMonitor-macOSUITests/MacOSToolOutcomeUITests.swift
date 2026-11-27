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
        // The field is prefilled with the last-used target, so empty it first.
        clearText(in: app.textFields["ping_textfield_host"])

        let runButton = requireExists(
            app.buttons["ping_button_run"],
            message: "Ping run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Run should be disabled with empty host")

        clearAndTypeText("127.0.0.1", into: app.textFields["ping_textfield_host"])
        XCTAssertTrue(runButton.isEnabled, "Run should be enabled after entering host")

        runButton.click()

        // Verify RESULT DATA appears. The chart only renders once ≥2 successful
        // pings arrive, and the Clear button only renders when results exist,
        // so either appearing proves the ping service populated output.
        XCTAssertTrue(
            waitForEither(
                [ui("ping_label_latencyChart"), app.buttons["ping_button_clear"]],
                timeout: 20
            ),
            "Ping should produce chart or clearable result output against 127.0.0.1"
        )

        // Click again to stop if still running (the button reads "Stop" then).
        if runButton.exists && runButton.label == "Stop" {
            runButton.click()
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

        selectDifferentOption(in: countPicker)

        closeTool(closeButtonID: "ping_button_close", cardID: "tools_card_ping")
    }

    // MARK: - Traceroute

    func testTracerouteValidationRunAndCloseOutcome() {
        openTool(cardID: "tools_card_traceroute", sheetElement: "traceroute_textfield_host")
        // The field is prefilled with the last-used target, so empty it first.
        clearText(in: app.textFields["traceroute_textfield_host"])

        let runButton = requireExists(
            app.buttons["traceroute_button_run"],
            message: "Traceroute run button should exist"
        )
        XCTAssertFalse(runButton.isEnabled, "Run should be disabled with empty host")

        clearAndTypeText("1.1.1.1", into: app.textFields["traceroute_textfield_host"])
        XCTAssertTrue(runButton.isEnabled, "Run should be enabled after entering host")

        runButton.click()

        // Verify at least one hop row is rendered — the service streams hops as
        // they arrive. Each hop row carries `traceroute_section_hops` (the ForEach's
        // id replaces the row's own `traceroute_row_<n>`), so its appearance proves
        // real data landed in the results area (not just a state flip).
        XCTAssertTrue(
            ui("traceroute_section_hops").firstMatch.waitForExistence(timeout: 25),
            "Traceroute should render at least hop #1 against 1.1.1.1"
        )

        if runButton.exists && runButton.label == "Stop" {
            runButton.click()
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

        selectDifferentOption(in: hopsPicker)

        closeTool(closeButtonID: "traceroute_button_close", cardID: "tools_card_traceroute")
    }

    // MARK: - Port Scanner

    func testPortScannerValidationRunAndCloseOutcome() {
        openTool(cardID: "tools_card_port_scanner", sheetElement: "portScan_textfield_host")
        // The field is prefilled with the last-used target, so empty it first.
        clearText(in: app.textFields["portScan_textfield_host"])

        let scanButton = requireExists(
            app.buttons["portScan_button_scan"],
            message: "Port scanner scan button should exist"
        )
        XCTAssertFalse(scanButton.isEnabled, "Scan should be disabled with empty host")

        clearAndTypeText("127.0.0.1", into: app.textFields["portScan_textfield_host"])
        XCTAssertTrue(scanButton.isEnabled, "Scan should be enabled after entering host")

        scanButton.click()

        // After the scan completes, the Clear button appears only when `results`
        // is non-empty — verifying the scan actually populated rows. The default
        // preset scans 15 common ports, so every port produces a `portScan_row_*`
        // (open or closed) entry.
        XCTAssertTrue(
            app.buttons["portScan_button_clear"].waitForExistence(timeout: 30),
            "Port scanner should produce result rows against 127.0.0.1"
        )

        closeTool(closeButtonID: "portScan_button_close", cardID: "tools_card_port_scanner")
    }

    func testPortScannerPresetPickerIsInteractive() {
        openTool(cardID: "tools_card_port_scanner", sheetElement: "portScan_textfield_host")

        let presetPicker = requireExists(
            app.popUpButtons["portScan_picker_preset"],
            message: "Port scanner preset picker should exist"
        )
        XCTAssertTrue(presetPicker.isEnabled, "Preset picker should be interactive")

        selectDifferentOption(in: presetPicker)

        closeTool(closeButtonID: "portScan_button_close", cardID: "tools_card_port_scanner")
    }

    // MARK: - DNS Lookup

    func testDNSLookupValidationRunClearAndCloseOutcome() {
        openTool(cardID: "tools_card_dns_lookup", sheetElement: "dns_textfield_hostname")
        // The field is prefilled with the last-used target, so empty it first.
        clearText(in: app.textFields["dns_textfield_hostname"])

        let lookupButton = requireExists(
            app.buttons["dns_button_lookup"],
            message: "DNS lookup button should exist"
        )
        XCTAssertFalse(lookupButton.isEnabled, "Lookup should be disabled with empty hostname")

        clearAndTypeText("example.com", into: app.textFields["dns_textfield_hostname"])
        XCTAssertTrue(lookupButton.isEnabled, "Lookup should be enabled after entering hostname")

        lookupButton.click()

        // The results ForEach carries `dns_section_results` and is wrapped in
        // `if !results.isEmpty`. Its appearance proves real records rendered.
        let resultsSection = ui("dns_section_results")
        XCTAssertTrue(
            resultsSection.waitForExistence(timeout: 20),
            "DNS lookup should render the results section with live data for example.com"
        )

        let clearButton = app.buttons["dns_button_clear"]
        XCTAssertTrue(clearButton.exists, "Clear button should be visible once DNS results exist")
        clearButton.click()
        XCTAssertTrue(
            waitForDisappearance(clearButton, timeout: 5),
            "Clear button should disappear after clearing DNS results"
        )
        XCTAssertTrue(
            waitForDisappearance(resultsSection, timeout: 5),
            "DNS results section should disappear after Clear"
        )

        closeTool(closeButtonID: "dns_button_close", cardID: "tools_card_dns_lookup")
    }

    func testDNSLookupRecordTypePickerIsInteractive() {
        openTool(cardID: "tools_card_dns_lookup", sheetElement: "dns_textfield_hostname")

        let typePicker = requireExists(
            app.popUpButtons["dns_picker_type"],
            message: "DNS record type picker should exist"
        )
        XCTAssertTrue(typePicker.isEnabled, "Record type picker should be interactive")

        selectDifferentOption(in: typePicker)

        closeTool(closeButtonID: "dns_button_close", cardID: "tools_card_dns_lookup")
    }

    // MARK: - WHOIS

    func testWHOISValidationRunClearAndCloseOutcome() {
        openTool(cardID: "tools_card_whois", sheetElement: "whois_textfield_domain")
        // The field is prefilled with the last-used target, so empty it first.
        clearText(in: app.textFields["whois_textfield_domain"])

        let lookupButton = requireExists(
            app.buttons["whois_button_lookup"],
            message: "WHOIS lookup button should exist"
        )
        XCTAssertFalse(lookupButton.isEnabled, "Lookup should be disabled with empty domain")

        clearAndTypeText("example.com", into: app.textFields["whois_textfield_domain"])
        XCTAssertTrue(lookupButton.isEnabled, "Lookup should be enabled after entering domain")

        lookupButton.click()

        // `whois_picker_viewmode` is gated on `result != nil`, and
        // `whois_section_parsed` only renders when the parsed result view is
        // visible — so either proves real WHOIS data returned.
        let viewModePicker = ui("whois_picker_viewmode").firstMatch
        let parsedSection = ui("whois_section_parsed")
        let clearButton = app.buttons["whois_button_clear"]
        XCTAssertTrue(
            waitForEither([viewModePicker, parsedSection, clearButton], timeout: 35),
            "WHOIS lookup should produce parsed result data for example.com"
        )

        if clearButton.exists {
            clearButton.click()
            XCTAssertTrue(
                waitForDisappearance(clearButton, timeout: 5),
                "Clear button should disappear after clearing WHOIS results"
            )
            XCTAssertTrue(
                waitForDisappearance(viewModePicker, timeout: 5),
                "View mode picker should disappear when WHOIS result is cleared"
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
            app.radioGroups["speedTest_picker_duration"],
            message: "Duration picker should exist"
        )

        // The result container `speedTest_section_results` renders the
        // latency/download/upload/server labels. They remain present across
        // idle/running/complete states; here we just verify they render at all
        // after the test enters the running phase.
        startButton.click()

        let stopButton = app.buttons["speedTest_button_stop"]
        XCTAssertTrue(
            stopButton.waitForExistence(timeout: 8),
            "Stop button should appear after starting speed test"
        )

        requireExists(
            ui("speedTest_section_results").firstMatch,
            timeout: 5,
            message: "Speed test results section should render with live data fields"
        )
        requireExists(
            ui("speedTest_label_latency").firstMatch,
            message: "Latency label should be rendered in speed test results"
        )
        requireExists(
            ui("speedTest_label_download").firstMatch,
            message: "Download label should be rendered in speed test results"
        )
        requireExists(
            ui("speedTest_label_upload").firstMatch,
            message: "Upload label should be rendered in speed test results"
        )
        requireExists(
            ui("speedTest_label_server").firstMatch,
            message: "Server label should be rendered in speed test results"
        )

        stopButton.click()

        XCTAssertTrue(
            app.buttons["speedTest_button_start"].waitForExistence(timeout: 8),
            "Start button should reappear after stopping speed test"
        )

        closeTool(closeButtonID: "speedTest_button_close", cardID: "tools_card_speed_test")
    }

    func testSpeedTestDurationPickerSegments() {
        openTool(cardID: "tools_card_speed_test", sheetElement: "speedTest_button_start")

        let picker = requireExists(
            app.radioGroups["speedTest_picker_duration"],
            message: "Duration picker should exist"
        )
        // A segmented picker is a RadioGroup of RadioButtons on macOS 27.
        let segments = picker.radioButtons
        XCTAssertEqual(segments.count, 3, "Duration picker should have 3 segments (5s, 10s, 30s)")

        // Verify segment selection actually changes state — click a segment that is not selected
        let all = segments.allElementsBoundByIndex
        guard let selected = all.first(where: { stringValue($0) == "1" }),
              let other = all.last(where: { stringValue($0) != "1" }) else {
            return XCTFail("Duration picker should have one selected and one unselected segment")
        }
        other.click()
        XCTAssertEqual(stringValue(other), "1",
                       "A duration segment should be selected after clicking it")
        XCTAssertEqual(stringValue(selected), "0",
                       "The previous duration segment should be deselected")

        // Restore the original selection
        selected.click()

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

        sendButton.click()

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
        refreshButton.click()

        // After refresh, verify the results area is present — either service rows
        // appeared or the refresh at least completed without error (close button
        // is still accessible and refresh button is still present).
        requireExists(
            app.buttons["bonjour_button_close"],
            message: "Close button should remain after refresh"
        )
        XCTAssertTrue(refreshButton.exists,
                      "Refresh button should remain available after refresh completes")

        // Verify the Bonjour results area has content structure
        let hasContentStructure = waitForEither([
            app.tables.firstMatch,
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'bonjour_row_'")
            ).firstMatch,
            ui("bonjour_label_empty"),
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'No services' OR label CONTAINS[c] 'No results'"
                    + " OR value CONTAINS[c] 'No services'")
            ).firstMatch
        ], timeout: 5)
        XCTAssertTrue(hasContentStructure,
                      "Bonjour browser should show service list or empty state after refresh")

        closeTool(closeButtonID: "bonjour_button_close", cardID: "tools_card_bonjour_browser")
    }

    // MARK: - Helpers

    /// Open a pop-up picker, choose an option other than the current one,
    /// verify the picker shows it, and put the original back. The menu is read from the picker itself:
    /// `app.menuItems` starts with the Apple menu in the menu bar.
    private func selectDifferentOption(in picker: XCUIElement) {
        let valueBefore = stringValue(picker)
        picker.click()

        let options = picker.menuItems
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 3),
                      "\(picker) should open its menu")
        let name: (XCUIElement) -> String = { $0.title.isEmpty ? $0.label : $0.title }
        guard let other = options.allElementsBoundByIndex.first(where: {
            $0.isEnabled && !name($0).isEmpty && name($0) != valueBefore
        }) else {
            app.typeKey(.escape, modifierFlags: [])
            return XCTFail("\(picker) should offer an option other than '\(valueBefore)'")
        }
        let chosen = name(other)
        other.click()

        XCTAssertEqual(stringValue(picker), chosen,
                       "\(picker) should show the option that was selected")

        // Restore the original option: the ping count is saved in app settings.
        picker.click()
        requireExists(picker.menuItems[valueBefore], timeout: 3,
                      message: "\(picker) should still offer '\(valueBefore)'").click()
    }
}
