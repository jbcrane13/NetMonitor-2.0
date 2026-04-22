import XCTest

/// Edge-case and error-state verification for the four macOS UI areas
/// upgraded under PRD-issue-174: tool outcomes, settings persistence,
/// sidebar navigation, and device context menu.
///
/// The existing upgrade tests cover the golden path (valid input → visible
/// result). These tests complement them by exercising the error paths and
/// boundary conditions the user can actually hit:
///
///   - Input validation disables the run/send/lookup button.
///   - Typing something *invalid* (not just empty) keeps it disabled, and
///     correcting the input re-enables it.
///   - Surfacing error UI when a subnet calculation fails, and clearing it.
///   - Settings dependent controls are disabled when their parent toggle is off.
///   - Re-selecting the same sidebar section is a safe no-op.
///   - Rapid sidebar switching settles on the last selection.
///   - Escape key dismisses a device context menu without side effects.
@MainActor
final class EdgeCasesAndErrorStatesUITests: MacOSUITestCase {

    // MARK: - Tool: empty-input validation

    /// Parameter-table sweep of the "empty input disables primary action"
    /// contract. Individually opening every tool keeps failures localised
    /// to the specific tool rather than the first one that regresses.
    private struct EmptyInputCase {
        let cardID: String
        let anchorField: String
        let actionButton: String
        let closeButton: String
    }

    private let emptyInputCases: [EmptyInputCase] = [
        EmptyInputCase(cardID: "tools_card_ping",
                       anchorField: "ping_textfield_host",
                       actionButton: "ping_button_run",
                       closeButton: "ping_button_close"),
        EmptyInputCase(cardID: "tools_card_traceroute",
                       anchorField: "traceroute_textfield_host",
                       actionButton: "traceroute_button_run",
                       closeButton: "traceroute_button_close"),
        EmptyInputCase(cardID: "tools_card_port_scanner",
                       anchorField: "portScan_textfield_host",
                       actionButton: "portScan_button_scan",
                       closeButton: "portScan_button_close"),
        EmptyInputCase(cardID: "tools_card_dns_lookup",
                       anchorField: "dns_textfield_hostname",
                       actionButton: "dns_button_lookup",
                       closeButton: "dns_button_close"),
        EmptyInputCase(cardID: "tools_card_whois",
                       anchorField: "whois_textfield_domain",
                       actionButton: "whois_button_lookup",
                       closeButton: "whois_button_close")
    ]

    func testToolsDisablePrimaryActionForEmptyInput() {
        for tool in emptyInputCases {
            openTool(cardID: tool.cardID, sheetElement: tool.anchorField)

            let button = requireExists(
                app.buttons[tool.actionButton],
                message: "\(tool.actionButton) should exist in \(tool.cardID)"
            )
            XCTAssertFalse(button.isEnabled,
                           "\(tool.actionButton) should be disabled when input is empty")

            closeTool(closeButtonID: tool.closeButton, cardID: tool.cardID)
        }
    }

    // MARK: - Tool: WoL invalid MAC address validation

    func testWakeOnLANStaysDisabledForInvalidMACAndEnablesAfterCorrection() {
        openTool(cardID: "tools_card_wake_on_lan", sheetElement: "wol_textfield_mac")

        let sendButton = requireExists(
            app.buttons["wol_button_send"],
            message: "WoL send button should exist"
        )
        XCTAssertFalse(sendButton.isEnabled,
                       "Send should be disabled with empty MAC")

        // Invalid: too short / contains non-hex characters.
        clearAndTypeText("ZZ:ZZ:ZZ", into: app.textFields["wol_textfield_mac"])
        XCTAssertFalse(sendButton.isEnabled,
                       "Send should remain disabled for invalid MAC 'ZZ:ZZ:ZZ'")

        // Invalid: wrong length (10 hex chars instead of 12).
        clearAndTypeText("AA:BB:CC:DD:EE", into: app.textFields["wol_textfield_mac"])
        XCTAssertFalse(sendButton.isEnabled,
                       "Send should remain disabled for under-length MAC")

        // Correcting to a well-formed MAC must enable send.
        clearAndTypeText("AA:BB:CC:DD:EE:FF", into: app.textFields["wol_textfield_mac"])
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabledPredicate, object: sendButton)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 3), .completed,
                       "Send should become enabled after MAC is corrected")

        closeTool(closeButtonID: "wol_button_close", cardID: "tools_card_wake_on_lan")
    }

    // MARK: - Tool: Subnet Calculator error card and recovery

    func testSubnetCalculatorShowsErrorCardForInvalidCIDRAndClearsIt() {
        openTool(cardID: "tools_card_subnet_calculator",
                 sheetElement: "subnetCalc_textfield_cidr")

        // Type something syntactically invalid — must go through the
        // `errorMessage` path and render the error card.
        clearAndTypeText("not-a-cidr", into: app.textFields["subnetCalc_textfield_cidr"])
        let calcButton = requireExists(
            app.buttons["subnetCalc_button_calculate"],
            message: "Calculate button should exist"
        )
        XCTAssertTrue(calcButton.isEnabled,
                      "Calculate should be enabled once non-empty input is present")
        calcButton.tap()

        let errorCard = ui("subnetCalc_card_error")
        XCTAssertTrue(errorCard.waitForExistence(timeout: 5),
                      "Error card should appear when CIDR is invalid")

        // Results section must NOT render when the input errored.
        XCTAssertFalse(ui("subnetCalc_section_results").exists,
                       "Results section should not render for invalid CIDR")

        // Clear recovers: error card disappears, clear button leaves.
        let clearButton = requireExists(
            app.buttons["subnetCalc_button_clear"],
            message: "Clear button should appear once an error exists"
        )
        clearButton.tap()

        XCTAssertTrue(waitForDisappearance(errorCard, timeout: 3),
                      "Error card should disappear after Clear")
        XCTAssertTrue(waitForDisappearance(clearButton, timeout: 3),
                      "Clear button should disappear after clearing state")

        // And entering a valid CIDR afterwards now produces the results section.
        clearAndTypeText("192.168.1.0/24",
                         into: app.textFields["subnetCalc_textfield_cidr"])
        app.buttons["subnetCalc_button_calculate"].tap()
        XCTAssertTrue(ui("subnetCalc_section_results").waitForExistence(timeout: 5),
                      "Results section should render after recovering from error")

        captureScreenshot(named: "SubnetCalc_Error_Then_Recover")

        closeTool(closeButtonID: "subnetCalc_button_close",
                  cardID: "tools_card_subnet_calculator")
    }

    // MARK: - Settings: dependent controls disabled when parent toggle is off

    /// The Notifications tab declares `.disabled(!notificationsEnabled)` on
    /// three controls: `notifyTargetDown`, `notifyTargetRecovery`, and
    /// `latencyThreshold`. Disabling the parent toggle must propagate.
    func testDisablingNotificationsDisablesDependentControls() {
        // Tap the Settings sidebar row directly (actual ID is
        // `sidebar_nav_settings` — the `navigateToSidebar` helper's
        // `sidebar_\(section)` form does not currently match).
        let settingsRow = ui("sidebar_nav_settings")
        requireExists(settingsRow, timeout: 5,
                      message: "sidebar_nav_settings should exist")
        settingsRow.tap()
        requireExists(ui("contentView_nav_settings"), timeout: 5,
                      message: "Settings container should mount")

        // Try clicking multiple variants of the Notifications tab row.
        let tabCandidates: [XCUIElement] = [
            ui("settings_tab_Notifications"),
            ui("settings_tab_notifications"),
            app.staticTexts["Notifications"],
            app.outlines.staticTexts["Notifications"]
        ]
        for candidate in tabCandidates where candidate.waitForExistence(timeout: 2) {
            candidate.tap()
            break
        }

        let parentToggle = requireExists(
            app.checkBoxes["settings_toggle_notificationsEnabled"], timeout: 5,
            message: "Notifications enabled toggle should exist"
        )

        // Make sure the parent toggle is ON so dependents are in the enabled
        // baseline we can then compare against.
        if (parentToggle.value as? String) == "0" {
            parentToggle.tap()
        }

        let dependents: [XCUIElement] = [
            app.checkBoxes["settings_toggle_notifyTargetDown"],
            app.checkBoxes["settings_toggle_notifyTargetRecovery"],
            app.sliders["settings_slider_latencyThreshold"]
        ]
        for dependent in dependents {
            requireExists(dependent, timeout: 3,
                          message: "Dependent control \(dependent) should exist")
            XCTAssertTrue(dependent.isEnabled,
                          "\(dependent) should be enabled while notifications are ON")
        }

        // Flip parent OFF and verify each dependent disables.
        parentToggle.tap()

        for dependent in dependents {
            let disabledPredicate = NSPredicate(format: "isEnabled == false")
            let expectation = XCTNSPredicateExpectation(predicate: disabledPredicate,
                                                        object: dependent)
            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 3), .completed,
                           "\(dependent) should be disabled after notifications are turned OFF")
        }

        // Restore parent to avoid leaving UserDefaults in a surprising state
        // for a following test case that relies on notifications being on.
        parentToggle.tap()
    }

    // MARK: - Sidebar: re-select same section is idempotent

    func testReselectingSameSidebarSectionKeepsContentMounted() {
        let devicesRow = ui("sidebar_nav_devices")
        let container = ui("contentView_nav_devices")
        let marker = ui("devices_textfield_search")

        XCTAssertTrue(devicesRow.waitForExistence(timeout: 5),
                      "Devices sidebar row should exist")
        devicesRow.tap()

        XCTAssertTrue(container.waitForExistence(timeout: 5),
                      "Devices container should mount on first selection")
        XCTAssertTrue(marker.waitForExistence(timeout: 5),
                      "Devices search field should render on first selection")

        // Tap the same row again. The container + content marker should
        // still be present — tapping the currently-selected row must NOT
        // unmount or swap the detail pane.
        devicesRow.tap()

        XCTAssertTrue(container.exists,
                      "Devices container should remain after re-selecting the same row")
        XCTAssertTrue(marker.exists,
                      "Devices search field should remain after re-selecting the same row")

        // Tap a third time for good measure.
        devicesRow.tap()
        XCTAssertTrue(marker.exists,
                      "Devices content should still be stable after repeated re-selection")
    }

    // MARK: - Sidebar: rapid-fire switches settle on the last selection

    func testRapidSidebarSwitchesSettleOnFinalSelection() {
        let devicesRow = ui("sidebar_nav_devices")
        let toolsRow = ui("sidebar_nav_tools")
        let settingsRow = ui("sidebar_nav_settings")

        XCTAssertTrue(devicesRow.waitForExistence(timeout: 5))
        XCTAssertTrue(toolsRow.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsRow.waitForExistence(timeout: 5))

        // Rapidly hop between sections without waiting for settle.
        devicesRow.tap()
        toolsRow.tap()
        devicesRow.tap()
        settingsRow.tap()
        toolsRow.tap()
        settingsRow.tap()

        // Final selection should be Settings — verify the pane and its
        // unique content marker land.
        XCTAssertTrue(ui("contentView_nav_settings").waitForExistence(timeout: 5),
                      "Settings container should be visible after rapid switching")
        XCTAssertTrue(ui("settings_nav_sidebar").waitForExistence(timeout: 5),
                      "Settings tab sidebar should render as final state")

        // And content from intermediate selections should have unmounted —
        // otherwise the detail pane is stacking every selection.
        XCTAssertFalse(ui("contentView_nav_devices").exists,
                       "Devices pane must not persist after switching to settings")
        XCTAssertFalse(ui("tools_section_diagnostics").exists,
                       "Tools content must not persist after switching to settings")
    }

    // MARK: - Device context menu: Escape dismisses cleanly

    func testContextMenuEscapeDismissesWithoutTriggeringAction() {
        // Relaunch with the seed flag so we have a deterministic device.
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--seed-test-device"]
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["XCUITest"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10),
                      "Main window should appear after relaunch")

        // Navigate to Devices (identifier is `sidebar_nav_devices`).
        let devicesRow = ui("sidebar_nav_devices")
        requireExists(devicesRow, timeout: 5,
                      message: "sidebar_nav_devices should exist")
        devicesRow.tap()

        let seededIP = "192.168.77.77"
        let card = ui("devices_card_\(seededIP)")
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "Seeded device card should appear before opening menu")

        card.rightClick()

        // Menu entry must surface — otherwise this test isn't exercising
        // the dismissal path.
        let menuAppeared = waitForEither(
            [
                app.menuItems["devices_menu_ping"],
                app.buttons["devices_menu_ping"]
            ],
            timeout: 3
        )
        XCTAssertTrue(menuAppeared, "Context menu should open on right-click")

        // Press Escape and verify no side effects (no sheet, no removal).
        app.typeKey(.escape, modifierFlags: [])

        // Poll briefly to give SwiftUI a chance to close the menu.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline,
              app.menuItems["devices_menu_ping"].exists
                  || app.buttons["devices_menu_ping"].exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertFalse(ui("devices_section_pingSheet").exists,
                       "Ping sheet should NOT appear when menu was dismissed via Escape")
        XCTAssertFalse(ui("devices_section_portScanSheet").exists,
                       "Port scan sheet should NOT appear when menu was dismissed via Escape")
        XCTAssertTrue(card.exists,
                      "Device card must still be present — Escape should not remove it")
    }
}
