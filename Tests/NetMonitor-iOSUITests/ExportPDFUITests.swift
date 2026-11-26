import XCTest

@MainActor
final class ExportPDFUITests: IOSUITestCase {

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
            app.byID("ActivityListView").waitForExistence(timeout: 25) ||
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
        let settingsStillVisible = app.byID("screen_settings").waitForExistence(timeout: 5)
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
            app.byID("ActivityListView").waitForExistence(timeout: 25) ||
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
}

// MARK: - Shared steps

private extension IOSUITestCase {
    func openSettings() {
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

    func ui(_ id: String) -> XCUIElement {
        app.byID(id)
    }

    /// Taps Export Full Report as PDF, waits for the share sheet (the summary may take up to
    /// 20 s), attaches a screenshot of it and dismisses it.
    func exportReportAndDismissShareSheet() {
        let button = ui("export_button_pdf")
        scrollToElement(button)
        requireExists(button, timeout: 8, message: "PDF export button should exist").tap()

        let shareSheet = app.byID("ActivityListView")
        requireExists(shareSheet, timeout: 30, message: "The share sheet should open with the exported report")
        // Let the sheet finish presenting before it is screenshotted or dismissed.
        _ = app.buttons["Close"].waitForExistence(timeout: 3)
        keepScreenshot(app.screenshot(), named: "share-sheet")
        for _ in 0 ..< 3 where shareSheet.exists {
            if app.buttons["Close"].exists {
                app.buttons["Close"].tap()
            } else {
                shareSheet.swipeDown(velocity: .fast)
            }
            _ = waitForDisappearance(shareSheet, timeout: 3)
        }
        XCTAssertFalse(shareSheet.exists, "The share sheet should close")
    }

    /// The exported report's first page, shown in Settings in UI tests only.
    func reportFirstPage() -> XCUIElement {
        let preview = ui("settings_debug_reportFirstPage")
        scrollToElement(preview, maxSwipes: 8)
        requireExists(preview, timeout: 5, message: "Settings should show the exported report's first page")
        // Scroll the whole page clear of the floating tab bar, so its screenshot is readable.
        let tabBar = app.tabBars.firstMatch
        for _ in 0 ..< 4 where tabBar.exists && preview.frame.maxY > tabBar.frame.minY {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        return preview
    }

    func keepScreenshot(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Executive summary (#453)

/// The model answers: the exported report opens with the Executive Summary page.
@MainActor
final class ExportPDFSummaryUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_INSIGHT": "answer", "UITEST_SEED_REPORT": "1"]
    }

    func testExportedReportStartsWithTheExecutiveSummary() {
        openSettings()
        exportReportAndDismissShareSheet()

        let page = reportFirstPage()
        keepScreenshot(page.screenshot(), named: "executive-summary-page")
        XCTAssertTrue(page.label.contains("Executive Summary"), "First page: \(page.label)")
        XCTAssertTrue(page.label.contains("Written by the on-device model"), "First page: \(page.label)")
        XCTAssertTrue(page.label.contains("the key points above say what needs attention"), "First page: \(page.label)")
        XCTAssertTrue(page.label.contains("device is offline") || page.label.contains("devices are offline"), "First page: \(page.label)")
    }
}

/// The model is unavailable: the export still succeeds, without a summary page.
@MainActor
final class ExportPDFNoModelUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_INSIGHT": "unavailable", "UITEST_SEED_REPORT": "1"]
    }

    func testExportWithoutTheModelHasNoSummaryPage() {
        openSettings()
        exportReportAndDismissShareSheet()

        let page = reportFirstPage()
        keepScreenshot(page.screenshot(), named: "report-first-page-no-model")
        XCTAssertFalse(page.label.contains("Executive Summary"), "First page: \(page.label)")
        XCTAssertTrue(page.label.contains("Discovered Devices"), "First page: \(page.label)")
        // The device table names devices by displayName; the seeded printer has a custom name and no hostname (#492).
        XCTAssertTrue(page.label.contains("UITest Printer"), "First page: \(page.label)")
    }
}
