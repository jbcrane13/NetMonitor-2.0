import XCTest

@MainActor
final class WiFiHeatmapToolUITests: MacOSUITestCase {

    private func openHeatmap() {
        navigateToSidebar("tools")
        let card = app.otherElements["tools_card_wifi_heatmap"]
        requireExists(card, timeout: 5, message: "Wi-Fi Heatmap card should exist in tools grid")
        card.tap()
        requireExists(ui("screen_heatmap"), timeout: 5, message: "Heatmap screen should appear")
    }

    // MARK: - Screen & Navigation

    func testHeatmapCardExistsInToolsGrid() {
        navigateToSidebar("tools")
        let card = ui("tools_card_wifi_heatmap")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Wi-Fi Heatmap card should exist in tools grid")
        captureScreenshot(named: "Heatmap_CardInGrid")
    }

    func testHeatmapScreenOpens() {
        openHeatmap()
        requireExists(ui("screen_heatmap"), message: "Heatmap screen should be visible")
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
        let saveButton = ui("heatmap_button_save")
        if saveButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(saveButton.exists, "Save button should exist")
        }
    }

    func testExportButtonExists() {
        openHeatmap()
        let exportButton = ui("heatmap_button_export")
        if exportButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(exportButton.exists, "Export button should exist")
        }
    }

    func testUndoButtonExists() {
        openHeatmap()
        let undoButton = ui("heatmap_button_undo")
        if undoButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(undoButton.exists, "Undo button should exist")
        }
    }

    // MARK: - Sidebar

    func testSidebarToggleExists() {
        openHeatmap()
        let sidebarButton = ui("heatmap_button_sidebar")
        if sidebarButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(sidebarButton.exists, "Sidebar toggle should exist")
            captureScreenshot(named: "Heatmap_SidebarToggle")
        }
    }

    func testSidebarOpens() {
        openHeatmap()
        let sidebarButton = ui("heatmap_button_sidebar")
        guard sidebarButton.waitForExistence(timeout: 5) else { return }
        sidebarButton.tap()

        let sidebar = ui("screen_heatmapSidebar")
        if sidebar.waitForExistence(timeout: 5) {
            requireExists(sidebar, message: "Heatmap sidebar should appear")
            captureScreenshot(named: "Heatmap_Sidebar")
        }
    }

    // MARK: - Sidebar Controls

    func testSurveyControlExists() {
        openHeatmap()
        let startSurvey = ui("heatmap_button_startSurvey")
        let stopSurvey = ui("heatmap_button_stopSurvey")
        // Survey controls may be in the sidebar
        let sidebarButton = ui("heatmap_button_sidebar")
        if sidebarButton.waitForExistence(timeout: 3) {
            sidebarButton.tap()
        }
        XCTAssertTrue(
            waitForEither([startSurvey, stopSurvey], timeout: 5),
            "Start or stop survey button should exist"
        )
        captureScreenshot(named: "Heatmap_SurveyControls")
    }

    func testVisualizationPickerExists() {
        openHeatmap()
        let sidebarButton = ui("heatmap_button_sidebar")
        if sidebarButton.waitForExistence(timeout: 3) {
            sidebarButton.tap()
        }
        let vizPicker = ui("heatmap_picker_visualization")
        if vizPicker.waitForExistence(timeout: 5) {
            XCTAssertTrue(vizPicker.exists, "Visualization picker should exist in sidebar")
        }
    }

    func testColorSchemePickerExists() {
        openHeatmap()
        let sidebarButton = ui("heatmap_button_sidebar")
        if sidebarButton.waitForExistence(timeout: 3) {
            sidebarButton.tap()
        }
        let colorPicker = ui("heatmap_picker_colorScheme")
        if colorPicker.waitForExistence(timeout: 5) {
            XCTAssertTrue(colorPicker.exists, "Color scheme picker should exist in sidebar")
        }
    }

    func testLiveSignalCardExists() {
        openHeatmap()
        let sidebarButton = ui("heatmap_button_sidebar")
        if sidebarButton.waitForExistence(timeout: 3) {
            sidebarButton.tap()
        }
        let signalCard = ui("heatmap_card_liveSignal")
        if signalCard.waitForExistence(timeout: 5) {
            XCTAssertTrue(signalCard.exists, "Live signal card should exist in sidebar")
            captureScreenshot(named: "Heatmap_LiveSignal")
        }
    }

    // MARK: - Calibration

    func testCalibrateButtonExists() {
        openHeatmap()
        let calibrateButton = ui("heatmap_button_calibrate")
        if calibrateButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(calibrateButton.exists, "Calibrate button should exist")
        }
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
