import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Settings
        let sidebar = app.staticTexts["sidebar_settings"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Settings Detail Pane

    func testSettingsDetailExists() {
        XCTAssertTrue(app.otherElements["detail_settings"].waitForExistence(timeout: 3))
    }

    // MARK: - Settings Tabs

    func testGeneralTabExists() {
        XCTAssertTrue(app.staticTexts["settings_tab_general"].waitForExistence(timeout: 3))
    }

    func testMonitoringTabExists() {
        XCTAssertTrue(app.staticTexts["settings_tab_monitoring"].waitForExistence(timeout: 3))
    }

    func testNotificationsTabExists() {
        XCTAssertTrue(app.staticTexts["settings_tab_notifications"].waitForExistence(timeout: 3))
    }

    func testNetworkTabExists() {
        XCTAssertTrue(app.staticTexts["settings_tab_network"].waitForExistence(timeout: 3))
    }

    func testDataTabExists() {
        XCTAssertTrue(app.staticTexts["settings_tab_data"].waitForExistence(timeout: 3))
    }

    func testAppearanceTabExists() {
        XCTAssertTrue(app.staticTexts["settings_tab_appearance"].waitForExistence(timeout: 3))
    }

    func testCompanionTabExists() {
        XCTAssertTrue(app.staticTexts["settings_tab_companion"].waitForExistence(timeout: 3))
    }

    // MARK: - General Settings

    func testGeneralSettingsControls() {
        app.staticTexts["settings_tab_general"].tap()

        XCTAssertTrue(app.checkBoxes["settings_toggle_launchAtLogin"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.checkBoxes["settings_toggle_showInMenuBar"].exists)
        XCTAssertTrue(app.checkBoxes["settings_toggle_showInDock"].exists)
    }

    // MARK: - Monitoring Settings

    func testMonitoringSettingsControls() {
        app.staticTexts["settings_tab_monitoring"].tap()

        XCTAssertTrue(app.popUpButtons["settings_picker_defaultInterval"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.popUpButtons["settings_picker_defaultTimeout"].exists)
        XCTAssertTrue(app.checkBoxes["settings_toggle_retryEnabled"].exists)
    }

    // MARK: - Notification Settings

    func testNotificationSettingsControls() {
        app.staticTexts["settings_tab_notifications"].tap()

        XCTAssertTrue(app.checkBoxes["settings_toggle_notificationsEnabled"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.checkBoxes["settings_toggle_notifyTargetDown"].exists)
        XCTAssertTrue(app.checkBoxes["settings_toggle_notifyTargetRecovery"].exists)
        XCTAssertTrue(app.sliders["settings_slider_latencyThreshold"].exists)
    }

    // MARK: - Network Settings

    func testNetworkSettingsControls() {
        app.staticTexts["settings_tab_network"].tap()

        XCTAssertTrue(app.popUpButtons["settings_picker_preferredInterface"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.checkBoxes["settings_toggle_useSystemProxy"].exists)
    }

    // MARK: - Data Settings

    func testDataSettingsControls() {
        app.staticTexts["settings_tab_data"].tap()

        XCTAssertTrue(app.popUpButtons["settings_picker_historyRetention"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings_button_export"].exists)
        XCTAssertTrue(app.buttons["settings_button_clearData"].exists)
    }

    // MARK: - Appearance Settings

    func testAppearanceSettingsControls() {
        app.staticTexts["settings_tab_appearance"].tap()

        XCTAssertTrue(app.buttons["settings_color_cyan"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings_color_blue"].exists)
        XCTAssertTrue(app.buttons["settings_color_purple"].exists)
        XCTAssertTrue(app.buttons["settings_color_pink"].exists)
        XCTAssertTrue(app.buttons["settings_color_green"].exists)
        XCTAssertTrue(app.buttons["settings_color_orange"].exists)
        XCTAssertTrue(app.checkBoxes["settings_toggle_compactMode"].exists)
    }

    // MARK: - Companion Settings

    func testCompanionSettingsControls() {
        app.staticTexts["settings_tab_companion"].tap()

        XCTAssertTrue(app.checkBoxes["settings_toggle_companionEnabled"].waitForExistence(timeout: 3))
    }

    func testCompanionServicePortFieldVisible() {
        app.staticTexts["settings_tab_companion"].tap()

        // Port field should be visible when companion is enabled
        let enabledToggle = app.checkBoxes["settings_toggle_companionEnabled"]
        XCTAssertTrue(enabledToggle.waitForExistence(timeout: 3))

        // If companion is enabled, port field should exist
        if enabledToggle.value as? String == "1" {
            XCTAssertTrue(app.textFields["settings_textfield_servicePort"].exists)
        }
    }

    // MARK: - Tab Navigation

    func testNavigateThroughAllTabs() {
        let tabs = [
            "settings_tab_general",
            "settings_tab_monitoring",
            "settings_tab_notifications",
            "settings_tab_network",
            "settings_tab_data",
            "settings_tab_appearance",
            "settings_tab_companion"
        ]

        for tabID in tabs {
            let tab = app.staticTexts[tabID]
            XCTAssertTrue(tab.waitForExistence(timeout: 3), "\(tabID) should exist")
            tab.tap()
        }
    }
}
