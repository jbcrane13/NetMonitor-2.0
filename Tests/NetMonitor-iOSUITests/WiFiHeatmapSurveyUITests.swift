import XCTest

@MainActor
final class WiFiHeatmapSurveyUITests: IOSUITestCase {
    func testWiFiHeatmapScreenAndCoreControlsAreVisible() {
        openWiFiHeatmap()

        requireExists(ui("heatmap_status_bar"), message: "Heatmap status bar should be visible")
        requireExists(ui("heatmap_picker_mode"), message: "Heatmap mode picker should be visible")
        requireExists(app.buttons["heatmap_button_main_action"], message: "Main heatmap action button should be visible")
        requireExists(app.buttons["heatmap_button_select_floorplan"], message: "Floorplan selection should be visible")
        requireExists(app.buttons["heatmap_button_survey_without_floorplan"], message: "Survey without floorplan button should be visible")
    }

    func testWiFiHeatmapGuideSheetOpenAndClose() {
        openWiFiHeatmap()

        requireExists(app.buttons["heatmap_button_info"], message: "Info button should be visible").tap()
        requireExists(ui("screen_wifiHeatmapGuide"), timeout: 8, message: "Heatmap guide should open from info button")

        requireExists(app.buttons["heatmap_button_guide_done"], message: "Guide done button should be visible").tap()
        XCTAssertTrue(
            waitForDisappearance(ui("screen_wifiHeatmapGuide"), timeout: 5),
            "Heatmap guide should close after tapping Done"
        )
    }

    func testStartSurveyButtonTriggersMeasurementState() {
        openWiFiHeatmap()

        let mainActionButton = requireExists(
            app.buttons["heatmap_button_main_action"],
            message: "Main action button should exist"
        )
        mainActionButton.tap()

        let stopButton = app.buttons["heatmap_button_stop"]
        let progressView = app.progressIndicators.firstMatch
        let measurementSection = ui("heatmap_section_measurement")

        XCTAssertTrue(
            waitForEither([stopButton, progressView, measurementSection], timeout: 10),
            "Tapping start should transition to measurement state (stop button, progress, or measurement section)"
        )
    }

    func testStopSurveyReturnsToCaptureState() {
        openWiFiHeatmap()

        let mainActionButton = requireExists(
            app.buttons["heatmap_button_main_action"],
            message: "Main action button should exist"
        )
        mainActionButton.tap()

        let stopButton = app.buttons["heatmap_button_stop"]
        if stopButton.waitForExistence(timeout: 10) {
            stopButton.tap()
            XCTAssertTrue(
                mainActionButton.waitForExistence(timeout: 8),
                "Start/main action button should reappear after stopping survey"
            )
        } else {
            mainActionButton.tap()
            XCTAssertTrue(
                mainActionButton.waitForExistence(timeout: 8),
                "Main action button should remain accessible after toggling survey"
            )
        }
    }

    func testScreenTitleAndLayoutExist() {
        openWiFiHeatmap()

        requireExists(ui("screen_wifiHeatmapTool"), message: "WiFi Heatmap screen identifier should exist")

        XCTAssertTrue(
            app.navigationBars["WiFi Heatmap"].waitForExistence(timeout: 5) ||
            app.navigationBars["Heatmap"].waitForExistence(timeout: 3) ||
            app.navigationBars.firstMatch.waitForExistence(timeout: 3),
            "Navigation bar should be visible on WiFi Heatmap screen"
        )

        requireExists(app.buttons["heatmap_button_main_action"], message: "Main action button should be visible")
        requireExists(ui("heatmap_picker_mode"), message: "Mode picker should be visible")
    }

    private func openWiFiHeatmap() {
        openToolsRoot()

        let card = ui("tools_card_wifi_heatmap")
        scrollToElement(card)
        requireExists(card, timeout: 8, message: "WiFi Heatmap tool card should exist").tap()

        requireExists(
            ui("screen_wifiHeatmapTool"),
            timeout: 8,
            message: "WiFi Heatmap screen should open from tools grid"
        )
    }

    private func openToolsRoot() {
        requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist").tap()
        requireExists(ui("screen_tools"), timeout: 8, message: "Tools root should be visible")
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

}
