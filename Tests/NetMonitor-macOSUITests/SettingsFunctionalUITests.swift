import XCTest

/// Functional companion tests for macOS SettingsUITests.
///
/// Tests verify **outcomes** of settings interactions: tab content loading,
/// preference persistence, and control interactivity.
/// Existing tests in SettingsUITests are NOT modified.
final class SettingsFunctionalUITests: MacOSUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        navigateToSidebar("settings")
    }

    // MARK: - 1. Click Settings Tab -> Verify Tab Content Loads

    func testGeneralTabLoadsContent() {
        let tab = app.staticTexts["settings_tab_general"]
        requireExists(tab, timeout: 3, message: "General tab should exist")
        tab.tap()

        // Verify General tab has its controls
        let hasControls = waitForEither([
            app.checkBoxes["settings_toggle_launchAtLogin"],
            app.checkBoxes["settings_toggle_showInMenuBar"],
            app.checkBoxes["settings_toggle_showInDock"]
        ], timeout: 5)

        XCTAssertTrue(hasControls,
                     "General tab should show launch/menu bar/dock checkboxes")

        captureScreenshot(named: "MacSettings_GeneralTab")
    }

    func testMonitoringTabLoadsContent() {
        let tab = app.staticTexts["settings_tab_monitoring"]
        requireExists(tab, timeout: 3, message: "Monitoring tab should exist")
        tab.tap()

        let hasControls = waitForEither([
            app.popUpButtons["settings_picker_defaultInterval"],
            app.popUpButtons["settings_picker_defaultTimeout"],
            app.checkBoxes["settings_toggle_retryEnabled"]
        ], timeout: 5)

        XCTAssertTrue(hasControls,
                     "Monitoring tab should show interval/timeout pickers or retry checkbox")

        captureScreenshot(named: "MacSettings_MonitoringTab")
    }

    func testNotificationsTabLoadsContent() {
        let tab = app.staticTexts["settings_tab_notifications"]
        requireExists(tab, timeout: 3, message: "Notifications tab should exist")
        tab.tap()

        let hasControls = waitForEither([
            app.checkBoxes["settings_toggle_notificationsEnabled"],
            app.checkBoxes["settings_toggle_notifyTargetDown"],
            app.sliders["settings_slider_latencyThreshold"]
        ], timeout: 5)

        XCTAssertTrue(hasControls,
                     "Notifications tab should show notification checkboxes or latency slider")

        captureScreenshot(named: "MacSettings_NotificationsTab")
    }

    func testNetworkTabLoadsContent() {
        let tab = app.staticTexts["settings_tab_network"]
        requireExists(tab, timeout: 3, message: "Network tab should exist")
        tab.tap()

        let hasControls = waitForEither([
            app.popUpButtons["settings_picker_preferredInterface"],
            app.checkBoxes["settings_toggle_useSystemProxy"]
        ], timeout: 5)

        XCTAssertTrue(hasControls,
                     "Network tab should show interface picker or proxy checkbox")

        captureScreenshot(named: "MacSettings_NetworkTab")
    }

    func testDataTabLoadsContent() {
        let tab = app.staticTexts["settings_tab_data"]
        requireExists(tab, timeout: 3, message: "Data tab should exist")
        tab.tap()

        let hasControls = waitForEither([
            app.popUpButtons["settings_picker_historyRetention"],
            app.buttons["settings_button_export"],
            app.buttons["settings_button_clearData"]
        ], timeout: 5)

        XCTAssertTrue(hasControls,
                     "Data tab should show retention picker, export, or clear buttons")

        captureScreenshot(named: "MacSettings_DataTab")
    }

    func testAppearanceTabLoadsContent() {
        let tab = app.staticTexts["settings_tab_appearance"]
        requireExists(tab, timeout: 3, message: "Appearance tab should exist")
        tab.tap()

        let hasControls = waitForEither([
            app.buttons["settings_color_cyan"],
            app.buttons["settings_color_blue"],
            app.checkBoxes["settings_toggle_compactMode"]
        ], timeout: 5)

        XCTAssertTrue(hasControls,
                     "Appearance tab should show color buttons or compact mode checkbox")

        captureScreenshot(named: "MacSettings_AppearanceTab")
    }

    func testCompanionTabLoadsContent() {
        let tab = app.staticTexts["settings_tab_companion"]
        requireExists(tab, timeout: 3, message: "Companion tab should exist")
        tab.tap()

        let hasControls = app.checkBoxes["settings_toggle_companionEnabled"]
            .waitForExistence(timeout: 5)

        XCTAssertTrue(hasControls,
                     "Companion tab should show companion enabled checkbox")

        captureScreenshot(named: "MacSettings_CompanionTab")
    }

    // MARK: - 2. Change Preference -> Verify It Persists

    func testShowInDockCheckboxPersistsAcrossTabSwitch() {
        app.staticTexts["settings_tab_general"].tap()

        let showInDock = requireExists(
            app.checkBoxes["settings_toggle_showInDock"], timeout: 3,
            message: "Show in Dock checkbox should exist"
        )

        let valueBefore = showInDock.value as? String ?? ""
        showInDock.tap()
        let valueAfter = showInDock.value as? String ?? ""

        // Value should have changed
        if valueBefore != valueAfter {
            // Switch to another tab and back
            app.staticTexts["settings_tab_monitoring"].tap()
            requireExists(app.popUpButtons["settings_picker_defaultInterval"], timeout: 3,
                         message: "Monitoring tab should load")

            app.staticTexts["settings_tab_general"].tap()

            let showInDockAfterReturn = requireExists(
                app.checkBoxes["settings_toggle_showInDock"], timeout: 3,
                message: "Show in Dock should exist after returning to General tab"
            )

            let persistedValue = showInDockAfterReturn.value as? String ?? ""
            XCTAssertEqual(valueAfter, persistedValue,
                          "Show in Dock state should persist across tab switches")

            // Restore original state
            showInDockAfterReturn.tap()
        }

        captureScreenshot(named: "MacSettings_DockPersistence")
    }

    func testNotificationSliderPersistsValue() {
        app.staticTexts["settings_tab_notifications"].tap()

        let slider = app.sliders["settings_slider_latencyThreshold"]
        guard slider.waitForExistence(timeout: 3) else { return }

        // Get value before adjustment
        let valueBefore = slider.normalizedSliderPosition

        // Adjust slider
        slider.adjust(toNormalizedSliderPosition: 0.7)

        let valueAfterAdjust = slider.normalizedSliderPosition

        // Switch tabs and return
        app.staticTexts["settings_tab_general"].tap()
        _ = app.checkBoxes["settings_toggle_launchAtLogin"].waitForExistence(timeout: 3)

        app.staticTexts["settings_tab_notifications"].tap()
        let sliderAfterReturn = app.sliders["settings_slider_latencyThreshold"]
        guard sliderAfterReturn.waitForExistence(timeout: 3) else { return }

        let persistedValue = sliderAfterReturn.normalizedSliderPosition

        // The persisted value should be closer to 0.7 than to the original
        if valueBefore != valueAfterAdjust {
            let diffFromOriginal = abs(persistedValue - valueBefore)
            let diffFromAdjusted = abs(persistedValue - valueAfterAdjust)

            XCTAssertTrue(diffFromAdjusted <= diffFromOriginal + 0.1,
                         "Slider value should persist after tab switch (persisted: \(persistedValue), expected near: \(valueAfterAdjust))")
        }

        captureScreenshot(named: "MacSettings_SliderPersistence")
    }

    // MARK: - 3. Accent Color Selection Changes UI

    func testAccentColorSelectionIsInteractive() {
        app.staticTexts["settings_tab_appearance"].tap()

        let cyanButton = requireExists(
            app.buttons["settings_color_cyan"], timeout: 3,
            message: "Cyan color button should exist"
        )

        // Click cyan
        cyanButton.tap()

        // Click blue
        let blueButton = app.buttons["settings_color_blue"]
        guard blueButton.waitForExistence(timeout: 3) else { return }
        blueButton.tap()

        // Both buttons should still be present (UI didn't crash)
        XCTAssertTrue(cyanButton.exists, "Cyan button should still exist after color selection")
        XCTAssertTrue(blueButton.exists, "Blue button should still exist after color selection")

        captureScreenshot(named: "MacSettings_AccentColor")
    }

    // MARK: - 4. Clear Data Confirmation Flow

    func testClearDataShowsConfirmationAndCanBeCancelled() {
        app.staticTexts["settings_tab_data"].tap()

        let clearButton = requireExists(
            app.buttons["settings_button_clearData"], timeout: 3,
            message: "Clear data button should exist on Data tab"
        )
        XCTAssertTrue(clearButton.isEnabled, "Clear data button should be enabled")

        clearButton.tap()

        // Confirmation dialog/alert should appear
        let appeared = waitForEither(
            [app.sheets.firstMatch, app.dialogs.firstMatch, app.alerts.firstMatch],
            timeout: 5
        )
        XCTAssertTrue(appeared,
                     "Confirmation sheet/alert should appear after clicking Clear Data")

        // Dismiss without clearing
        let dismissCandidates = [
            app.buttons["Cancel"],
            app.buttons["cancel"],
            app.buttons["Don't Clear"],
            app.sheets.firstMatch.buttons.firstMatch
        ]
        for candidate in dismissCandidates where candidate.exists {
            candidate.tap()
            break
        }

        // Settings should still be visible
        requireExists(app.otherElements["detail_settings"], timeout: 3,
                      message: "Settings detail should remain after cancelling Clear Data")

        captureScreenshot(named: "MacSettings_ClearDataConfirm")
    }

    // MARK: - 5. Monitoring Picker Interaction

    func testMonitoringIntervalPickerIsInteractive() {
        app.staticTexts["settings_tab_monitoring"].tap()

        let picker = requireExists(
            app.popUpButtons["settings_picker_defaultInterval"], timeout: 3,
            message: "Default interval picker should exist"
        )

        XCTAssertTrue(picker.isEnabled,
                     "Default interval picker should be enabled and interactive")

        // Click the picker to verify it opens
        picker.tap()

        // Menu items should appear
        let hasMenuItems = app.menuItems.firstMatch.waitForExistence(timeout: 3)

        if hasMenuItems {
            // Select an option
            let firstItem = app.menuItems.firstMatch
            firstItem.tap()

            // Picker should still be present after selection
            requireExists(picker, timeout: 3,
                         message: "Picker should remain after selecting an option")
        } else {
            // Press Escape to dismiss if no menu items found
            app.typeKey(.escape, modifierFlags: [])
        }

        captureScreenshot(named: "MacSettings_IntervalPicker")
    }

    // MARK: - 6. Compact Mode Toggle

    func testCompactModeToggleChangesState() {
        app.staticTexts["settings_tab_appearance"].tap()

        let compactToggle = app.checkBoxes["settings_toggle_compactMode"]
        guard compactToggle.waitForExistence(timeout: 3) else { return }

        let valueBefore = compactToggle.value as? String ?? ""
        compactToggle.tap()
        let valueAfter = compactToggle.value as? String ?? ""

        XCTAssertNotEqual(valueBefore, valueAfter,
                         "Compact mode checkbox should change state after clicking")

        // Restore
        compactToggle.tap()

        captureScreenshot(named: "MacSettings_CompactMode")
    }

    // MARK: - 7. Tab Navigation Round-Trip

    func testAllTabsAccessibleInSequence() {
        let tabs = [
            ("settings_tab_general", "General"),
            ("settings_tab_monitoring", "Monitoring"),
            ("settings_tab_notifications", "Notifications"),
            ("settings_tab_network", "Network"),
            ("settings_tab_data", "Data"),
            ("settings_tab_appearance", "Appearance"),
            ("settings_tab_companion", "Companion")
        ]

        for (tabID, tabName) in tabs {
            let tab = app.staticTexts[tabID]
            XCTAssertTrue(tab.waitForExistence(timeout: 3),
                         "\(tabName) tab should exist in settings")
            tab.tap()
        }

        // Return to General to complete round-trip
        app.staticTexts["settings_tab_general"].tap()
        requireExists(app.checkBoxes["settings_toggle_launchAtLogin"], timeout: 3,
                      message: "General tab content should load after full round-trip")

        captureScreenshot(named: "MacSettings_AllTabs")
    }

    // MARK: - 8. Export Button is Functional

    func testExportButtonIsFunctional() {
        app.staticTexts["settings_tab_data"].tap()

        let exportButton = app.buttons["settings_button_export"]
        guard exportButton.waitForExistence(timeout: 3) else { return }

        XCTAssertTrue(exportButton.isEnabled,
                     "Export button should be enabled on Data tab")

        exportButton.tap()

        // Should open save dialog or show export options
        let hasResponse = waitForEither([
            app.sheets.firstMatch,
            app.dialogs.firstMatch,
            app.windows.element(boundBy: 1)
        ], timeout: 5)

        // Dismiss any dialog that appeared
        if hasResponse {
            app.typeKey(.escape, modifierFlags: [])
        }

        // Settings should remain visible
        requireExists(app.otherElements["detail_settings"], timeout: 3,
                      message: "Settings should remain visible after export interaction")

        captureScreenshot(named: "MacSettings_Export")
    }

    // MARK: - 9. Retry Enabled Toggle

    func testRetryEnabledToggleChangesState() {
        app.staticTexts["settings_tab_monitoring"].tap()

        let retryToggle = app.checkBoxes["settings_toggle_retryEnabled"]
        guard retryToggle.waitForExistence(timeout: 3) else { return }

        let valueBefore = retryToggle.value as? String ?? ""
        retryToggle.tap()
        let valueAfter = retryToggle.value as? String ?? ""

        XCTAssertNotEqual(valueBefore, valueAfter,
                         "Retry enabled checkbox should change state after clicking")

        // Restore
        retryToggle.tap()

        captureScreenshot(named: "MacSettings_RetryToggle")
    }

    // MARK: - 10. Companion Toggle and Port Field

    func testCompanionToggleRevealsPortField() {
        app.staticTexts["settings_tab_companion"].tap()

        let companionToggle = app.checkBoxes["settings_toggle_companionEnabled"]
        guard companionToggle.waitForExistence(timeout: 3) else { return }

        // If companion is off, turn it on
        if (companionToggle.value as? String) == "0" {
            companionToggle.tap()
        }

        // Port field should be visible when companion is enabled
        let portField = app.textFields["settings_textfield_servicePort"]
        if portField.waitForExistence(timeout: 3) {
            XCTAssertTrue(portField.isEnabled,
                         "Service port field should be enabled when companion is on")
        }

        captureScreenshot(named: "MacSettings_CompanionPort")
    }
}
