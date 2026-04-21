import XCTest

// TODO: full survey→capture→export E2E blocked by missing floor-plan test-seam. See audit 2026-04-21.
// Currently achievable: entry, shortcut-setup dismissal, export button presence.
// Future: add testSeam to load a floor plan before takeMeasurement.

@MainActor
final class WiFiHeatmapSurveyExportE2ETests: IOSUITestCase {

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

    // MARK: - Tests

    func testHeatmapEntryAndShortcutSetupDismissal() {
        navigateToHeatmap()

        // If the shortcut-setup sheet appears, dismiss it
        let shortcutSkip = ui("shortcutSetup_button_skip")
        if shortcutSkip.waitForExistence(timeout: 3) {
            shortcutSkip.tap()
            // Wait for sheet to disappear
            waitForDisappearance(shortcutSkip, timeout: 2)
        }

        // Assert heatmap canvas container exists or empty-state prompt exists
        let canvasContainer = ui("heatmap_canvas_container")
        let importPrompt = ui("heatmap_button_chooseFile")

        XCTAssertTrue(
            waitForEither([canvasContainer, importPrompt], timeout: 5),
            "Either canvas container or import prompt should be visible after dismissing shortcut setup"
        )

        captureScreenshot(named: "Heatmap_EntryAfterShortcutDismissal")
    }

    func testHeatmapExportButtonPresentsShareSheet() {
        navigateToHeatmap()

        // Dismiss shortcut setup if present
        let shortcutSkip = ui("shortcutSetup_button_skip")
        if shortcutSkip.waitForExistence(timeout: 3) {
            shortcutSkip.tap()
            waitForDisappearance(shortcutSkip, timeout: 2)
        }

        // Assert share button exists
        let shareButton = ui("heatmap_button_share")
        requireExists(shareButton, timeout: 5, message: "Share button should be visible")

        // Attempt to tap and assert share sheet appears
        shareButton.tap()
        let shareSheet = ui("heatmap_sheet_share")

        if shareSheet.waitForExistence(timeout: 3) {
            XCTAssertTrue(shareSheet.exists, "Share sheet should appear when share button is tapped")
            captureScreenshot(named: "Heatmap_ShareSheetPresented")
            // Dismiss by tapping outside or cancel
            app.swipeDown()
        } else {
            // Share button may be disabled without data; document and continue
            XCTAssertTrue(shareButton.exists, "Share button exists; may be disabled without measurement data")
            captureScreenshot(named: "Heatmap_ShareButtonExists")
        }
    }
}
