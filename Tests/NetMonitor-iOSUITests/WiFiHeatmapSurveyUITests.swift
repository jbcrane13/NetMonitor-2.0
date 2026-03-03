import XCTest

@MainActor
final class WiFiHeatmapSurveyUITests: IOSUITestCase {

    // MARK: - Dashboard entry point

    func testWiFiHeatmapToolCardOpensDashboard() {
        // Navigation asserted inside openHeatmapDashboard()
        openHeatmapDashboard()
    }

    func testDashboardNetworkCardIsVisible() {
        openHeatmapDashboard()
        requireExists(
            ui("heatmap_dashboard_network_card"),
            message: "Dashboard network status card should be visible"
        )
    }

    func testNewScanButtonIsVisible() {
        openHeatmapDashboard()
        requireExists(
            app.buttons["heatmap_dashboard_button_new_scan"],
            message: "New Scan button should be visible on dashboard"
        )
    }

    // MARK: - Floor plan selection sheet

    func testNewScanOpensFloorPlanSelection() {
        openHeatmapDashboard()
        app.buttons["heatmap_dashboard_button_new_scan"].tap()
        requireExists(
            ui("screen_floorPlanSelection"),
            timeout: 8,
            message: "Floor plan selection sheet should appear after tapping New Scan"
        )
    }

    func testFloorPlanSelectionHasFreeformOption() {
        openHeatmapDashboard()
        app.buttons["heatmap_dashboard_button_new_scan"].tap()
        requireExists(ui("screen_floorPlanSelection"), timeout: 8, message: "Floor plan selection sheet should appear")
        requireExists(
            ui("floorplan_option_freeform"),
            message: "Freeform grid option should be visible in floor plan selection"
        )
    }

    func testFloorPlanSelectionCancelDismissesSheet() {
        openHeatmapDashboard()
        app.buttons["heatmap_dashboard_button_new_scan"].tap()
        requireExists(ui("screen_floorPlanSelection"), timeout: 8, message: "Floor plan selection sheet should appear")
        let cancelButton = ui("floorplan_button_cancel")
        if cancelButton.exists {
            cancelButton.tap()
        } else {
            app.swipeDown()
        }
        XCTAssertTrue(
            waitForDisappearance(ui("screen_floorPlanSelection"), timeout: 5),
            "Floor plan selection should be dismissed"
        )
    }

    // MARK: - Active survey screen

    func testFreeformSurveyScreenOpens() {
        openFreeformSurvey()
        requireExists(
            ui("screen_activeMappingSurvey"),
            timeout: 12,
            message: "Active survey screen should open after selecting freeform"
        )
    }

    func testActiveSurveyCloseButtonDismisses() {
        openFreeformSurvey()
        requireExists(ui("screen_activeMappingSurvey"), timeout: 12, message: "Active survey screen should be visible")
        requireExists(app.buttons["heatmap_survey_button_close"], timeout: 5, message: "Close button should be visible").tap()
        requireExists(
            ui("screen_heatmapDashboard"),
            timeout: 8,
            message: "Dashboard should be visible after closing active survey"
        )
    }

    // MARK: - Control strip overlays

    func testColorSchemeMenuIsAccessible() {
        openFreeformSurvey()
        requireExists(ui("screen_activeMappingSurvey"), timeout: 12, message: "Active survey screen should be visible")
        requireExists(
            ui("heatmap_menu_scheme"),
            message: "Color scheme menu should be accessible during survey"
        )
    }

    func testOverlayToggleDotsIsAccessible() {
        openFreeformSurvey()
        requireExists(ui("screen_activeMappingSurvey"), timeout: 12, message: "Active survey screen should be visible")
        requireExists(
            ui("heatmap_toggle_dots"),
            message: "Dots overlay toggle should be accessible during survey"
        )
    }

    // MARK: - Navigation helpers

    private func openHeatmapDashboard() {
        openToolsRoot()
        let card = ui("tools_card_wifi_heatmap")
        scrollToElement(card)
        requireExists(card, timeout: 8, message: "WiFi Heatmap tool card should be in the tools grid").tap()
        requireExists(
            ui("screen_heatmapDashboard"),
            timeout: 8,
            message: "Heatmap dashboard should open from tools grid"
        )
    }

    private func openFreeformSurvey() {
        openHeatmapDashboard()
        app.buttons["heatmap_dashboard_button_new_scan"].tap()
        requireExists(ui("screen_floorPlanSelection"), timeout: 8, message: "Floor plan selection should appear")
        requireExists(ui("floorplan_option_freeform"), timeout: 5, message: "Freeform option should be visible").tap()
    }

    private func openToolsRoot() {
        requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist").tap()
        requireExists(ui("screen_tools"), timeout: 8, message: "Tools root should be visible")
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
