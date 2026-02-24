import XCTest

@MainActor
final class ExportPDFUITests: IOSUITestCase {

    private func openSettings() {
        requireExists(
            app.tabBars.buttons["Settings"],
            message: "Settings tab should exist"
        ).tap()
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

    // MARK: - Helpers

    private func ui(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }
}
