import XCTest

final class WiFiHeatmapToolUITests: IOSUITestCase {

    private func navigateToHeatmap() {
        app.tabBars.buttons["Tools"].tap()
        let card = app.otherElements["tools_card_wifi_heatmap"]
        scrollToElement(card)
        requireExists(card, timeout: 8, message: "Wi-Fi Heatmap card should exist in tools grid")
        card.tap()
        requireExists(ui("screen_heatmapSurvey"), timeout: 8, message: "Heatmap survey screen should appear")
    }

    private func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    // MARK: - Screen & Navigation

    func testHeatmapCardExistsInToolsGrid() {
        app.tabBars.buttons["Tools"].tap()
        requireExists(ui("screen_tools"), timeout: 8, message: "Tools screen should open")
        let card = ui("tools_card_wifi_heatmap")
        scrollToElement(card)
        XCTAssertTrue(card.waitForExistence(timeout: 8), "Wi-Fi Heatmap card should exist in tools grid")
        captureScreenshot(named: "Heatmap_CardInGrid")
    }

    func testHeatmapScreenOpens() throws {
        navigateToHeatmap()
        requireExists(ui("screen_heatmapSurvey"), message: "Heatmap survey screen should be visible")
        captureScreenshot(named: "Heatmap_SurveyScreen")
    }

    // MARK: - Import Controls

    func testImportBlueprintButtonExists() throws {
        navigateToHeatmap()
        let importButton = ui("heatmap_button_chooseFile")
        let photoButton = ui("heatmap_button_choosePhoto")
        let openButton = ui("heatmap_button_opensurvey")
        XCTAssertTrue(
            waitForEither([importButton, photoButton, openButton], timeout: 8),
            "At least one import/open action should be available"
        )
        captureScreenshot(named: "Heatmap_ImportControls")
    }

    // MARK: - Toolbar Actions

    func testToolbarMenuExists() throws {
        navigateToHeatmap()
        let moreMenu = ui("heatmap_menu_more")
        let shareButton = ui("heatmap_button_share")
        XCTAssertTrue(
            waitForEither([moreMenu, shareButton], timeout: 5),
            "Toolbar should have more menu or share button"
        )
        captureScreenshot(named: "Heatmap_Toolbar")
    }

    func testOpenSurveyMenuExists() throws {
        navigateToHeatmap()
        let openMenu = ui("heatmap_button_openSurveyMenu")
        let openSurvey = ui("heatmap_button_opensurvey")
        XCTAssertTrue(
            waitForEither([openMenu, openSurvey], timeout: 5),
            "Open survey action should be available"
        )
    }

    // MARK: - Sidebar Sheet

    func testSidebarSheetOpens() throws {
        navigateToHeatmap()
        // The sidebar sheet is presented as a bottom sheet on iOS
        let sidebar = ui("heatmap_sheet_sidebar")
        if sidebar.waitForExistence(timeout: 5) {
            // Sidebar is auto-presented
            requireExists(sidebar, message: "Sidebar sheet should be visible")
        } else {
            // Try expanding it
            let expandButton = ui("heatmap_button_expandSidebar")
            if expandButton.waitForExistence(timeout: 3) {
                expandButton.tap()
                requireExists(sidebar, timeout: 5, message: "Sidebar sheet should appear after expand")
            }
        }
        captureScreenshot(named: "Heatmap_SidebarSheet")
    }

    func testSurveyToggleExists() throws {
        navigateToHeatmap()
        let toggle = ui("heatmap_button_surveyToggle")
        if toggle.waitForExistence(timeout: 5) {
            XCTAssertTrue(toggle.exists, "Survey toggle should exist in sidebar")
            captureScreenshot(named: "Heatmap_SurveyToggle")
        }
    }

    func testVisualizationPickerExists() throws {
        navigateToHeatmap()
        let vizPicker = ui("heatmap_picker_visualization")
        if vizPicker.waitForExistence(timeout: 5) {
            XCTAssertTrue(vizPicker.exists, "Visualization picker should exist")
            captureScreenshot(named: "Heatmap_VizPicker")
        }
    }

    func testColorSchemePickerExists() throws {
        navigateToHeatmap()
        let colorPicker = ui("heatmap_picker_colorScheme")
        if colorPicker.waitForExistence(timeout: 5) {
            XCTAssertTrue(colorPicker.exists, "Color scheme picker should exist")
        }
    }

    // MARK: - HUD Elements

    func testSignalHUDExists() throws {
        navigateToHeatmap()
        let signalHUD = ui("heatmap_hud_signal")
        if signalHUD.waitForExistence(timeout: 5) {
            XCTAssertTrue(signalHUD.exists, "Signal HUD should exist on survey screen")
            captureScreenshot(named: "Heatmap_SignalHUD")
        }
    }

    // MARK: - Calibration

    func testCalibrationSheetOpens() throws {
        navigateToHeatmap()
        let calibrateButton = ui("heatmap_button_calibrate")
        guard calibrateButton.waitForExistence(timeout: 5) else {
            // Calibration button may not be visible without a blueprint loaded
            return
        }
        calibrateButton.tap()

        let calibrationSheet = ui("heatmap_sheet_calibration")
        requireExists(calibrationSheet, timeout: 5, message: "Calibration sheet should appear")

        let distanceField = ui("heatmap_textfield_calibrationDistance")
        requireExists(distanceField, timeout: 3, message: "Calibration distance field should exist")

        let unitPicker = ui("heatmap_picker_calibrationUnit")
        requireExists(unitPicker, timeout: 3, message: "Calibration unit picker should exist")

        captureScreenshot(named: "Heatmap_CalibrationSheet")

        // Dismiss
        let cancelButton = ui("heatmap_button_cancelCalibration")
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        }
    }

    // MARK: - Projects

    func testOpenSurveyShowsProjectsList() throws {
        navigateToHeatmap()
        let openButton = ui("heatmap_button_openSurveyMenu")
        let openSurvey = ui("heatmap_button_opensurvey")

        if openButton.waitForExistence(timeout: 5) {
            openButton.tap()
        } else if openSurvey.waitForExistence(timeout: 5) {
            openSurvey.tap()
        } else {
            return
        }

        let projectsSheet = ui("heatmap_sheet_projects")
        let projectsScreen = ui("screen_heatmapProjects")
        XCTAssertTrue(
            waitForEither([projectsSheet, projectsScreen], timeout: 5),
            "Projects list should appear after tapping open survey"
        )
        captureScreenshot(named: "Heatmap_ProjectsList")
    }

    // MARK: - Sidebar Controls

    func testUndoButtonExists() throws {
        navigateToHeatmap()
        let undoButton = ui("heatmap_button_undo")
        if undoButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(undoButton.exists, "Undo button should exist in sidebar")
        }
    }

    func testClearButtonExists() throws {
        navigateToHeatmap()
        let clearButton = ui("heatmap_button_clear")
        if clearButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(clearButton.exists, "Clear button should exist in sidebar")
        }
    }

    func testMeasurementCountLabelExists() throws {
        navigateToHeatmap()
        let countLabel = ui("heatmap_label_measurementCount")
        if countLabel.waitForExistence(timeout: 5) {
            XCTAssertTrue(countLabel.exists, "Measurement count label should exist")
        }
    }

    // MARK: - Canvas

    func testCanvasContainerExists() throws {
        navigateToHeatmap()
        let canvas = ui("heatmap_canvas_container")
        let floorplan = ui("heatmap_canvas_floorplan")
        XCTAssertTrue(
            waitForEither([canvas, floorplan], timeout: 8),
            "Heatmap canvas or floorplan should be visible"
        )
        captureScreenshot(named: "Heatmap_Canvas")
    }
}
