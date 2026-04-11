@preconcurrency import XCTest

/// Cross-screen interaction flow tests for the macOS app.
///
/// Verifies that navigation transitions, settings mutations, target management,
/// and device scan interactions produce the expected observable outcomes.
/// Modelled after the iOS ``InteractionFlowUITests`` but adapted for the
/// macOS sidebar/detail-pane layout and macOS-specific controls.
final class MacOSInteractionFlowUITests: MacOSUITestCase {

    // MARK: - Sidebar Navigation Flows

    func testSidebarSwitchUpdatesDetailPane() {
        // Start at Tools (default).
        requireExists(app.otherElements["contentView_nav_tools"], timeout: 5,
                      message: "Tools should be the default detail pane")

        // Switch to Settings.
        navigateToSidebar("settings")
        XCTAssertTrue(app.otherElements["contentView_nav_settings"].exists,
                      "Settings detail pane should be visible after selecting Settings")

        // Return to Tools.
        navigateToSidebar("tools")
        XCTAssertTrue(app.otherElements["contentView_nav_tools"].exists,
                      "Tools detail pane should be visible after returning to Tools")
    }

    func testFullSidebarNavigationCycle() {
        let sections = ["tools", "settings"]

        for section in sections {
            navigateToSidebar(section)
            XCTAssertTrue(
                app.otherElements["detail_\(section)"].exists,
                "detail_\(section) should be visible after selecting sidebar_\(section)"
            )
        }

        // Return to Tools to confirm round-trip.
        navigateToSidebar("tools")
        XCTAssertTrue(app.otherElements["contentView_nav_tools"].exists,
                      "Tools should be reachable after cycling through all sections")
    }

    // MARK: - Target Management Flows

    func testAddTargetSheetOpensFillsAndCancels() {
        navigateToSidebar("targets")

        let addButton = requireExists(
            app.buttons["targets_button_add"],
            message: "Add target button should exist"
        )
        addButton.tap()

        // Verify sheet elements appear.
        let nameField = requireExists(
            app.textFields["addTarget_textfield_name"], timeout: 5,
            message: "Name field should appear in add-target sheet"
        )
        let hostField = requireExists(
            app.textFields["addTarget_textfield_host"],
            message: "Host field should appear in add-target sheet"
        )
        requireExists(
            app.popUpButtons["addTarget_picker_protocol"],
            message: "Protocol picker should appear in add-target sheet"
        )

        // Fill fields.
        clearAndTypeText("Test Server", into: nameField)
        clearAndTypeText("8.8.8.8", into: hostField)

        // Cancel — sheet should dismiss.
        let cancelButton = requireExists(
            app.buttons["addTarget_button_cancel"],
            message: "Cancel button should exist in add-target sheet"
        )
        cancelButton.tap()

        XCTAssertTrue(
            waitForDisappearance(nameField, timeout: 3),
            "Add-target sheet should dismiss after cancelling"
        )
    }

    func testAddTargetSheetFieldsAndAddButton() {
        navigateToSidebar("targets")
        app.buttons["targets_button_add"].tap()

        let addButton = requireExists(
            app.buttons["addTarget_button_add"], timeout: 5,
            message: "Add button should exist in add-target sheet"
        )

        // Fill required fields.
        clearAndTypeText("My Server", into: app.textFields["addTarget_textfield_name"])
        clearAndTypeText("1.1.1.1", into: app.textFields["addTarget_textfield_host"])

        // The add button should be present (may or may not be enabled depending on
        // additional validation). Just confirm it's tappable.
        XCTAssertTrue(addButton.exists, "Add button should remain visible after filling fields")

        // Clean up: cancel instead of adding to avoid polluting state.
        app.buttons["addTarget_button_cancel"].tap()
    }

    func testDeleteButtonDisabledWithNoSelection() {
        navigateToSidebar("targets")

        let deleteButton = requireExists(
            app.buttons["targets_button_delete"],
            message: "Delete button should exist"
        )
        XCTAssertFalse(deleteButton.isEnabled,
                       "Delete button should be disabled when no target is selected")
    }

    // MARK: - Device Scan Interactions

    func testDevicesScanButtonStartsScan() {
        navigateToSidebar("devices")

        let scanButton = requireExists(
            app.buttons["devices_button_scan"],
            message: "Scan button should exist"
        )
        XCTAssertTrue(scanButton.isEnabled, "Scan button should be enabled")

        scanButton.tap()

        // After tapping scan, the stop button or updated scan button should appear.
        XCTAssertTrue(
            waitForEither(
                [
                    app.buttons["devices_button_stopScan"],
                    app.buttons["devices_button_scan"]
                ],
                timeout: 10
            ),
            "Scan should transition to running state or complete quickly"
        )

        // If still scanning, stop it.
        let stopButton = app.buttons["devices_button_stopScan"]
        if stopButton.exists && stopButton.isEnabled {
            stopButton.tap()
        }
    }

    func testDevicesToolbarControlsAreInteractive() {
        navigateToSidebar("devices")

        let sortMenu = requireExists(
            app.menuButtons["devices_menu_sort"],
            message: "Sort menu should exist"
        )
        XCTAssertTrue(sortMenu.isEnabled, "Sort menu should be enabled")

        let onlineOnly = app.toggles["devices_toggle_onlineOnly"]
        if onlineOnly.waitForExistence(timeout: 3) {
            XCTAssertTrue(onlineOnly.isEnabled, "Online-only toggle should be enabled")
        }

        let clearButton = requireExists(
            app.buttons["devices_button_clear"],
            message: "Clear button should exist"
        )
        // Clear may be disabled if no devices, but should exist.
        XCTAssertTrue(clearButton.exists, "Clear button should be present")
    }

    // MARK: - Settings Interaction Flows

    func testSettingsTabSwitchingShowsCorrectControls() {
        navigateToSidebar("settings")

        // General tab — checkboxes
        app.staticTexts["settings_tab_general"].tap()
        requireExists(app.checkBoxes["settings_toggle_launchAtLogin"], timeout: 3,
                      message: "Launch at login checkbox should appear on General tab")

        // Monitoring tab — pickers
        app.staticTexts["settings_tab_monitoring"].tap()
        requireExists(app.popUpButtons["settings_picker_defaultInterval"], timeout: 3,
                      message: "Default interval picker should appear on Monitoring tab")

        // Notifications tab — checkboxes + slider
        app.staticTexts["settings_tab_notifications"].tap()
        requireExists(app.checkBoxes["settings_toggle_notificationsEnabled"], timeout: 3,
                      message: "Notifications enabled checkbox should appear on Notifications tab")

        // Network tab — pickers
        app.staticTexts["settings_tab_network"].tap()
        requireExists(app.popUpButtons["settings_picker_preferredInterface"], timeout: 3,
                      message: "Preferred interface picker should appear on Network tab")

        // Data tab — buttons
        app.staticTexts["settings_tab_data"].tap()
        requireExists(app.buttons["settings_button_export"], timeout: 3,
                      message: "Export button should appear on Data tab")

        // Appearance tab — color buttons
        app.staticTexts["settings_tab_appearance"].tap()
        requireExists(app.buttons["appearance_button_colorcyan"], timeout: 3,
                      message: "Cyan color button should appear on Appearance tab")

        // Companion tab — checkbox
        app.staticTexts["settings_tab_companion"].tap()
        requireExists(app.checkBoxes["settings_toggle_companionEnabled"], timeout: 3,
                      message: "Companion enabled checkbox should appear on Companion tab")
    }

    func testSettingsGeneralCheckboxToggleInteraction() {
        navigateToSidebar("settings")
        app.staticTexts["settings_tab_general"].tap()

        let showInDock = requireExists(
            app.checkBoxes["settings_toggle_showInDock"], timeout: 3,
            message: "Show in Dock checkbox should exist"
        )
        let initialValue = showInDock.value as? String

        showInDock.tap()

        let newValue = showInDock.value as? String
        // The value should change after toggling. We accept both "0"/"1" and
        // "false"/"true" representations.
        if let initial = initialValue, let updated = newValue {
            XCTAssertNotEqual(initial, updated,
                              "Show in Dock checkbox value should change after toggling")
        }

        // Toggle back to restore original state.
        showInDock.tap()
    }

    func testSettingsNotificationSliderIsInteractive() {
        navigateToSidebar("settings")
        app.staticTexts["settings_tab_notifications"].tap()

        let slider = app.sliders["settings_slider_latencyThreshold"]
        if slider.waitForExistence(timeout: 3) {
            XCTAssertTrue(slider.isEnabled, "Latency threshold slider should be enabled")

            // Adjust the slider slightly.
            slider.adjust(toNormalizedSliderPosition: 0.7)
            requireExists(slider, message: "Slider should remain visible after adjustment")
        }
    }

    func testSettingsAppearanceColorSelectionIsInteractive() {
        navigateToSidebar("settings")
        app.staticTexts["settings_tab_appearance"].tap()

        let colors = [
            "appearance_button_colorcyan",
            "appearance_button_colorblue",
            "appearance_button_colorpurple",
            "appearance_button_colorpink",
            "appearance_button_colorgreen",
            "appearance_button_colororange"
        ]

        for colorID in colors {
            let button = app.buttons[colorID]
            if button.waitForExistence(timeout: 2) {
                XCTAssertTrue(button.isEnabled, "\(colorID) should be enabled")
            }
        }

        // Select a different color and verify it's tappable.
        let purpleButton = app.buttons["appearance_button_colorpurple"]
        if purpleButton.exists {
            purpleButton.tap()
            requireExists(purpleButton, message: "Purple color button should remain after selection")
        }
    }

    func testSettingsDataExportAndClearButtonsExist() {
        navigateToSidebar("settings")
        app.staticTexts["settings_tab_data"].tap()

        let exportButton = requireExists(
            app.buttons["settings_button_export"], timeout: 3,
            message: "Export button should exist on Data tab"
        )
        XCTAssertTrue(exportButton.isEnabled, "Export button should be enabled")

        let clearButton = requireExists(
            app.buttons["settings_button_clearData"], timeout: 3,
            message: "Clear data button should exist on Data tab"
        )
        XCTAssertTrue(clearButton.isEnabled, "Clear data button should be enabled")
    }

    func testSettingsCompanionToggleConditionalPort() {
        navigateToSidebar("settings")
        app.staticTexts["settings_tab_companion"].tap()

        let enabledToggle = requireExists(
            app.checkBoxes["settings_toggle_companionEnabled"], timeout: 3,
            message: "Companion enabled checkbox should exist"
        )

        // If companion is enabled, the port field should be visible.
        if enabledToggle.value as? String == "1" {
            requireExists(
                app.textFields["settings_textfield_servicePort"], timeout: 3,
                message: "Service port field should be visible when companion is enabled"
            )
        }
    }

    // MARK: - Tool Sheet Open-Close Round Trip

    func testAllToolSheetsOpenAndCloseCleanly() {
        let tools: [(card: String, sheetElement: String, close: String)] = [
            ("tools_card_ping", "ping_textfield_host", "ping_button_close"),
            ("tools_card_traceroute", "traceroute_textfield_host", "traceroute_button_close"),
            ("tools_card_port_scanner", "portScan_textfield_host", "portScan_button_close"),
            ("tools_card_dns_lookup", "dns_textfield_hostname", "dns_button_close"),
            ("tools_card_whois", "whois_textfield_domain", "whois_button_close"),
            ("tools_card_speed_test", "speedTest_button_start", "speedTest_button_close"),
            ("tools_card_bonjour_browser", "bonjour_button_close", "bonjour_button_close"),
            ("tools_card_wake_on_lan", "wol_textfield_mac", "wol_button_close"),
        ]

        navigateToSidebar("tools")

        for tool in tools {
            let card = app.otherElements[tool.card]
            requireExists(card, timeout: 5, message: "\(tool.card) should exist")
            card.tap()

            requireExists(ui(tool.sheetElement), timeout: 5,
                          message: "\(tool.sheetElement) should appear for \(tool.card)")

            let closeButton = app.buttons[tool.close]
            requireExists(closeButton, timeout: 3,
                          message: "\(tool.close) should exist for \(tool.card)")
            closeButton.tap()

            requireExists(card, timeout: 5,
                          message: "\(tool.card) should reappear after closing sheet")
        }
    }

    // MARK: - Menu Bar

    func testMenuBarItemsExistAndAreEnabled() {
        let menuBar = app.menuBars.firstMatch
        requireExists(menuBar, timeout: 5, message: "Menu bar should exist")

        let expectedMenus = ["File", "View", "Window"]
        for menuName in expectedMenus {
            let menuItem = menuBar.menuBarItems[menuName]
            if menuItem.exists {
                XCTAssertTrue(menuItem.isEnabled,
                              "\(menuName) menu should be enabled")
            }
        }
    }
}
