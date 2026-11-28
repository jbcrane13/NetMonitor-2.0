import XCTest

@MainActor
final class SettingsUITests: MacOSUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        navigateToSidebar("settings")
    }

    // MARK: - Settings Detail Pane

    func testSettingsDetailExists() {
        requireExists(ui("contentView_nav_settings").firstMatch, timeout: 3,
                      message: "Settings detail pane should exist")
    }

    // MARK: - Settings Tabs

    func testGeneralTabExists() {
        requireExists(app.staticTexts["settings_tab_General"], timeout: 3,
                      message: "General tab should exist")
    }

    func testMonitoringTabExists() {
        requireExists(app.staticTexts["settings_tab_Monitoring"], timeout: 3,
                      message: "Monitoring tab should exist")
    }

    func testNotificationsTabExists() {
        requireExists(app.staticTexts["settings_tab_Notifications"], timeout: 3,
                      message: "Notifications tab should exist")
    }

    func testNetworkTabExists() {
        requireExists(app.staticTexts["settings_tab_Network"], timeout: 3,
                      message: "Network tab should exist")
    }

    func testDataTabExists() {
        requireExists(app.staticTexts["settings_tab_Data"], timeout: 3,
                      message: "Data tab should exist")
    }

    func testAppearanceTabExists() {
        requireExists(app.staticTexts["settings_tab_Appearance"], timeout: 3,
                      message: "Appearance tab should exist")
    }

    func testCompanionTabExists() {
        requireExists(app.staticTexts["settings_tab_Companion"], timeout: 3,
                      message: "Companion tab should exist")
    }

    // MARK: - General Settings

    func testGeneralSettingsControls() {
        app.staticTexts["settings_tab_General"].click()

        requireExists(app.switches["settings_toggle_launchAtLogin"], timeout: 3,
                      message: "Launch at login checkbox should exist on General tab")
        XCTAssertTrue(app.switches["settings_toggle_showInMenuBar"].exists,
                      "Show in menu bar checkbox should exist")
        XCTAssertTrue(app.switches["settings_toggle_showInDock"].exists,
                      "Show in dock checkbox should exist")
        captureScreenshot(named: "Settings_General")
    }

    func testGeneralTabCheckboxToggleChangesValue() {
        app.staticTexts["settings_tab_General"].click()

        let showInDock = requireExists(
            app.switches["settings_toggle_showInDock"], timeout: 3,
            message: "Show in Dock checkbox should exist on General tab"
        )
        let valueBefore = stringValue(showInDock)

        showInDock.click()

        let valueAfter = stringValue(showInDock)
        XCTAssertNotEqual(valueBefore, valueAfter,
                          "Show in Dock checkbox value should change after toggling")

        showInDock.click()
    }

    // MARK: - Monitoring Settings

    func testMonitoringSettingsControls() {
        app.staticTexts["settings_tab_Monitoring"].click()

        requireExists(app.popUpButtons["settings_picker_defaultInterval"], timeout: 3,
                      message: "Default interval picker should exist on Monitoring tab")
        XCTAssertTrue(app.popUpButtons["settings_picker_defaultTimeout"].exists,
                      "Default timeout picker should exist")
        XCTAssertTrue(app.switches["settings_toggle_retryEnabled"].exists,
                      "Retry enabled checkbox should exist")
    }

    func testMonitoringTabPickerIsInteractive() {
        app.staticTexts["settings_tab_Monitoring"].click()

        let picker = requireExists(
            app.popUpButtons["settings_picker_defaultInterval"], timeout: 3,
            message: "Default interval picker should exist on Monitoring tab"
        )
        XCTAssertTrue(picker.isEnabled, "Default interval picker should be enabled and interactive")
    }

    // MARK: - Notification Settings

    func testNotificationSettingsControls() {
        app.staticTexts["settings_tab_Notifications"].click()

        requireExists(app.switches["settings_toggle_notificationsEnabled"], timeout: 3,
                      message: "Notifications enabled checkbox should exist")
        XCTAssertTrue(app.switches["settings_toggle_notifyTargetDown"].exists,
                      "Notify target down checkbox should exist")
        XCTAssertTrue(app.switches["settings_toggle_notifyTargetRecovery"].exists,
                      "Notify target recovery checkbox should exist")
        XCTAssertTrue(app.sliders["settings_slider_latencyThreshold"].exists,
                      "Latency threshold slider should exist")
    }

    func testNotificationSliderInteraction() {
        app.staticTexts["settings_tab_Notifications"].click()

        // The slider is disabled until notifications are on.
        let notifications = app.switches["settings_toggle_notificationsEnabled"]
        if notifications.waitForExistence(timeout: 3), stringValue(notifications) == "0" {
            notifications.click()
        }
        let slider = requireExists(app.sliders["settings_slider_latencyThreshold"], timeout: 3,
                                   message: "Latency threshold slider should exist")

        XCTAssertTrue(slider.isEnabled, "Latency threshold slider should be enabled")
        slider.adjust(toNormalizedSliderPosition: 0.7)
        requireExists(slider, message: "Slider should remain visible after adjustment")
    }

    // MARK: - Network Settings

    func testNetworkSettingsControls() {
        app.staticTexts["settings_tab_Network"].click()

        requireExists(app.popUpButtons["settings_picker_preferredInterface"], timeout: 3,
                      message: "Preferred interface picker should exist on Network tab")
        XCTAssertTrue(app.switches["settings_toggle_useSystemProxy"].exists,
                      "Use system proxy checkbox should exist")
    }

    // MARK: - Data Settings

    func testDataSettingsControls() {
        app.staticTexts["settings_tab_Data"].click()

        requireExists(app.popUpButtons["settings_picker_historyRetention"], timeout: 3,
                      message: "History retention picker should exist on Data tab")
        XCTAssertTrue(app.buttons["settings_button_export"].exists,
                      "Export button should exist")
        XCTAssertTrue(app.buttons["settings_button_clearData"].exists,
                      "Clear data button should exist")
    }

    func testDataClearButtonShowsConfirmation() {
        app.staticTexts["settings_tab_Data"].click()

        let clearButton = requireExists(
            app.buttons["settings_button_clearData"], timeout: 3,
            message: "Clear data button should exist on Data tab"
        )
        XCTAssertTrue(clearButton.isEnabled, "Clear data button should be enabled")

        clearButton.click()

        let appeared = waitForEither(
            [app.sheets.firstMatch, app.dialogs.firstMatch, app.alerts.firstMatch],
            timeout: 5
        )
        XCTAssertTrue(appeared, "A confirmation sheet or alert should appear after tapping Clear Data")

        let dismissCandidates = [
            app.windows.buttons["Cancel"].firstMatch,
            app.windows.buttons["cancel"].firstMatch,
            app.buttons["Don't Clear"],
            app.sheets.firstMatch.buttons.firstMatch
        ]
        for candidate in dismissCandidates where candidate.exists {
            candidate.click()
            break
        }
    }

    // MARK: - Appearance Settings

    func testAppearanceSettingsControls() {
        app.staticTexts["settings_tab_Appearance"].click()

        requireExists(app.buttons["appearance_button_colorcyan"], timeout: 3,
                      message: "Cyan color button should exist on Appearance tab")
        XCTAssertTrue(app.buttons["appearance_button_colorblue"].exists, "Blue color button should exist")
        XCTAssertTrue(app.buttons["appearance_button_colorpurple"].exists, "Purple color button should exist")
        XCTAssertTrue(app.buttons["appearance_button_colorpink"].exists, "Pink color button should exist")
        XCTAssertTrue(app.buttons["appearance_button_colorgreen"].exists, "Green color button should exist")
        XCTAssertTrue(app.buttons["appearance_button_colororange"].exists, "Orange color button should exist")
        XCTAssertTrue(app.switches["settings_toggle_compactMode"].exists,
                      "Compact mode checkbox should exist")
    }

    func testAppearanceColorSelectionInteraction() {
        app.staticTexts["settings_tab_Appearance"].click()

        let cyanButton = requireExists(
            app.buttons["appearance_button_colorcyan"], timeout: 3,
            message: "Cyan color button should exist on Appearance tab"
        )
        cyanButton.click()
        requireExists(cyanButton, message: "Cyan button should remain after selection")

        let blueButton = app.buttons["appearance_button_colorblue"]
        if blueButton.waitForExistence(timeout: 2) {
            blueButton.click()
            requireExists(blueButton, message: "Blue button should remain after selection")
        }
    }

    func testTabPersistenceAfterSwitch() {
        app.staticTexts["settings_tab_Appearance"].click()
        requireExists(app.buttons["appearance_button_colorcyan"], timeout: 3,
                      message: "Cyan button should appear on Appearance tab")

        app.staticTexts["settings_tab_General"].click()
        requireExists(app.switches["settings_toggle_launchAtLogin"], timeout: 3,
                      message: "General tab controls should appear after switching")

        app.staticTexts["settings_tab_Appearance"].click()
        requireExists(app.buttons["appearance_button_colorcyan"], timeout: 3,
                      message: "Cyan button should still be present after switching back to Appearance tab")
    }

    // MARK: - Companion Settings

    func testCompanionSettingsControls() {
        app.staticTexts["settings_tab_Companion"].click()

        requireExists(app.switches["settings_toggle_companionEnabled"], timeout: 3,
                      message: "Companion enabled checkbox should exist")
    }

    func testCompanionServicePortFieldVisible() {
        app.staticTexts["settings_tab_Companion"].click()

        let enabledToggle = requireExists(
            app.switches["settings_toggle_companionEnabled"], timeout: 3,
            message: "Companion enabled checkbox should exist"
        )

        if stringValue(enabledToggle) == "1" {
            requireExists(app.textFields["settings_textfield_servicePort"], timeout: 3,
                          message: "Service port field should be visible when companion is enabled")
        }
    }

    // MARK: - Tab Navigation

    func testNavigateThroughAllTabs() {
        let tabs = [
            "settings_tab_General",
            "settings_tab_Monitoring",
            "settings_tab_Notifications",
            "settings_tab_Network",
            "settings_tab_Data",
            "settings_tab_Appearance",
            "settings_tab_Companion"
        ]

        for tabID in tabs {
            let tab = requireExists(app.staticTexts[tabID], timeout: 3,
                                    message: "\(tabID) should exist")
            tab.click()
        }
    }
}
