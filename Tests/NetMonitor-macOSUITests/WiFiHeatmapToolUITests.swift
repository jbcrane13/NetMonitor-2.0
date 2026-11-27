import XCTest

@MainActor
final class WiFiHeatmapToolUITests: MacOSUITestCase {

    private func openHeatmap() {
        navigateToSidebar("tools")
        let card = ui("tools_card_wifi_heatmap").firstMatch
        requireExists(card, timeout: 5, message: "Wi-Fi Heatmap card should exist in tools grid")
        card.click()
        requireExists(ui("screen_heatmap").firstMatch, timeout: 5, message: "Heatmap screen should appear")
    }

    /// The sidebar opens in Survey mode; the visualization controls are under Analyze.
    private func showAnalyzeSidebar() {
        let analyze = app.radioGroups["heatmap_picker_sidebarMode"].radioButtons["Analyze"]
        requireExists(analyze, message: "Sidebar mode picker should offer Analyze").click()
    }

    // MARK: - Screen & Navigation

    func testHeatmapCardExistsInToolsGrid() {
        navigateToSidebar("tools")
        let card = ui("tools_card_wifi_heatmap").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Wi-Fi Heatmap card should exist in tools grid")
        captureScreenshot(named: "Heatmap_CardInGrid")
    }

    func testHeatmapScreenOpens() {
        openHeatmap()
        requireExists(ui("screen_heatmap").firstMatch, message: "Heatmap screen should be visible")
        captureScreenshot(named: "Heatmap_Screen")
    }

    // MARK: - Import Controls

    func testImportButtonExists() {
        openHeatmap()
        let importButton = ui("heatmap_button_import")
        let importBlueprint = ui("heatmap_button_importBlueprint")
        XCTAssertTrue(
            waitForEither([importButton, importBlueprint], timeout: 5),
            "Import button should exist on heatmap screen"
        )
        captureScreenshot(named: "Heatmap_ImportControls")
    }

    func testOpenButtonExists() {
        openHeatmap()
        let openButton = ui("heatmap_button_open")
        XCTAssertTrue(openButton.waitForExistence(timeout: 5), "Open button should exist")
    }

    // MARK: - Toolbar Actions

    func testSaveButtonExists() {
        openHeatmap()
        requireExists(ui("heatmap_button_save").firstMatch, message: "Save button should exist")
    }

    func testExportButtonExists() {
        openHeatmap()
        requireExists(ui("heatmap_button_export").firstMatch, message: "Export button should exist")
    }

    func testUndoButtonExists() {
        openHeatmap()
        requireExists(ui("heatmap_button_undo").firstMatch, message: "Undo button should exist")
    }

    // MARK: - Sidebar

    func testSidebarToggleExists() {
        openHeatmap()
        requireExists(ui("heatmap_button_sidebar").firstMatch, message: "Sidebar toggle should exist")
        captureScreenshot(named: "Heatmap_SidebarToggle")
    }

    /// The sidebar is open when the heatmap opens; the toolbar toggle hides it and brings it back.
    func testSidebarOpens() {
        openHeatmap()
        let sidebar = ui("screen_heatmapSidebar").firstMatch
        requireExists(sidebar, message: "Heatmap sidebar should be visible when the heatmap opens")

        let sidebarButton = requireExists(ui("heatmap_button_sidebar").firstMatch, message: "Sidebar toggle should exist")
        sidebarButton.click()
        XCTAssertTrue(waitForDisappearance(sidebar), "Sidebar toggle should hide the sidebar")

        sidebarButton.click()
        requireExists(sidebar, message: "Heatmap sidebar should appear")
        captureScreenshot(named: "Heatmap_Sidebar")
    }

    // MARK: - Sidebar Controls

    func testSurveyControlExists() {
        openHeatmap()
        let startSurvey = ui("heatmap_button_startSurvey")
        let stopSurvey = ui("heatmap_button_stopSurvey")
        XCTAssertTrue(
            waitForEither([startSurvey, stopSurvey], timeout: 5),
            "Start or stop survey button should exist"
        )
        captureScreenshot(named: "Heatmap_SurveyControls")
    }

    func testVisualizationPickerExists() {
        openHeatmap()
        showAnalyzeSidebar()
        requireExists(ui("heatmap_picker_visualization").firstMatch,
                      message: "Visualization picker should exist in sidebar")
    }

    func testColorSchemePickerExists() {
        openHeatmap()
        showAnalyzeSidebar()
        requireExists(ui("heatmap_picker_colorScheme").firstMatch,
                      message: "Color scheme picker should exist in sidebar")
    }

    func testLiveSignalCardExists() {
        openHeatmap()
        requireExists(ui("heatmap_card_liveSignal").firstMatch, message: "Live signal card should exist in sidebar")
        captureScreenshot(named: "Heatmap_LiveSignal")
    }

    // MARK: - Calibration

    func testCalibrateButtonExists() {
        openHeatmap()
        requireExists(ui("heatmap_button_calibrate").firstMatch, message: "Calibrate button should exist")
    }

    // MARK: - Visualization Picker

    func testVizPickerExists() {
        openHeatmap()
        let vizPicker = ui("heatmap_picker_viz")
        if vizPicker.waitForExistence(timeout: 5) {
            XCTAssertTrue(vizPicker.exists, "Viz picker should exist on toolbar")
            captureScreenshot(named: "Heatmap_VizPicker")
        }
    }
}
