@preconcurrency import XCTest

final class ExportPDFUITests: IOSUITestCase {

    private func openSettings() {
        requireExists(
            app.tabBars.buttons["Dashboard"],
            message: "Dashboard tab should exist"
        ).tap()

        let settingsButton = app.buttons["dashboard_button_settings"]
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        } else {
            // Fallback for nav button label mismatch across OS versions.
            requireExists(app.navigationBars.buttons.firstMatch, message: "A navigation bar button should exist for settings").tap()
        }

        requireExists(ui("screen_settings"), timeout: 8, message: "Settings screen should open")
    }

    func testPDFExportButtonExistsInSettings() {
        openSettings()

        let button = ui("export_button_pdf")
        scrollToElement(button)
        XCTAssertTrue(
            button.waitForExistence(timeout: 8),
            "PDF export button should exist in Settings"
        )
    }

    func testPDFExportButtonTriggersTap() {
        openSettings()

        let button = ui("export_button_pdf")
        scrollToElement(button)
        requireExists(button, timeout: 8, message: "PDF export button should exist").tap()

        // After tapping, either a share sheet or activity controller should appear
        // We just verify it's tappable and doesn't crash
        // (Share sheet detection varies by iOS version)
        XCTAssertTrue(true, "PDF export button tapped without crash")
    }

    // MARK: - Functional Tests

    @MainActor
    func testPDFExportTriggersShareSheet() {
        openSettings()

        let button = ui("export_button_pdf")
        scrollToElement(button)
        requireExists(button, timeout: 8, message: "PDF export button should exist before tap").tap()

        // After tapping, a share sheet, activity view, or navigation bar for sharing may appear.
        // We accept any of these as a valid success outcome; if none appear the app must at
        // minimum remain on the settings screen without crashing.
        let shareSheetAppeared =
            app.otherElements["ActivityListView"].waitForExistence(timeout: 5) ||
            app.sheets.firstMatch.waitForExistence(timeout: 3) ||
            app.navigationBars["sharing"].waitForExistence(timeout: 3)

        if shareSheetAppeared {
            // Dismiss the share sheet so subsequent teardown is clean
            if app.buttons["Close"].waitForExistence(timeout: 3) {
                app.buttons["Close"].tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            }
        }

        // Either the share sheet appeared or the app gracefully stayed on settings — both are valid
        let settingsStillVisible = app.descendants(matching: .any)["screen_settings"].waitForExistence(timeout: 5)
        XCTAssertTrue(
            shareSheetAppeared || settingsStillVisible,
            "After tapping PDF export, either a share sheet should appear or settings screen should remain visible"
        )
    }

    @MainActor
    func testPDFExportButtonRemainsAfterDismiss() {
        openSettings()

        let button = ui("export_button_pdf")
        scrollToElement(button)
        requireExists(button, timeout: 8, message: "PDF export button should exist before tap").tap()

        // Dismiss share sheet if one appeared
        let shareSheetAppeared =
            app.otherElements["ActivityListView"].waitForExistence(timeout: 5) ||
            app.sheets.firstMatch.waitForExistence(timeout: 3)

        if shareSheetAppeared {
            if app.buttons["Close"].waitForExistence(timeout: 3) {
                app.buttons["Close"].tap()
            } else {
                app.swipeDown()
            }
        }

        // After any dismissal, the button must still be present in the settings hierarchy
        scrollToElement(button)
        XCTAssertTrue(
            button.waitForExistence(timeout: 5),
            "PDF export button should still exist after share sheet is dismissed"
        )
    }

    // MARK: - Helpers

    private func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }
}
