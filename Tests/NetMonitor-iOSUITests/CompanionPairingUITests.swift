import XCTest

/// Pairing with a Mac (#590), against the in-app fake Mac on loopback (`--fake-mac-pairing`),
/// which speaks the real TLS 1.3 protocol and confirms on its own after three seconds.
@MainActor
final class CompanionPairingUITests: IOSUITestCase {
    /// The fake Mac's typed code: a fixed, valid 125-bit code for this test only.
    private static let code = "14D2P-F2DBS-QQG28-T5CY4-TQKFF-K"

    override var additionalLaunchArguments: [String] { ["--fake-mac-pairing"] }
    override var additionalLaunchEnvironment: [String: String] { ["UITEST_PAIRING_CODE": Self.code] }

    func testPairWithTypedCode() throws {
        openPairingSheet()
        let row = requireExists(app.buttons["pairing_row_Test Mac"], timeout: 5, message: "The fake Mac should be listed")
        XCTAssertTrue(row.label.contains("Not paired"), "An unpaired Mac says so: \(row.label)")
        captureScreenshot(named: "590-01-mac-not-paired")

        row.tap()
        requireExists(app.byID("screen_pairWithMac"), timeout: 5, message: "Tapping an unpaired Mac opens pairing")
        let field = requireExists(app.textFields["pairMac_textfield_code"], message: "The code field should show")
        field.tap()
        field.typeText(Self.code)
        captureScreenshot(named: "590-02-code-typed")
        requireExists(app.buttons["pairMac_button_pairWithCode"], message: "Pair button").tap()

        let comparison = requireExists(
            app.staticTexts["pairMac_label_comparisonCode"], timeout: 8, message: "Both proofs pass: the comparison code shows"
        )
        XCTAssertEqual(comparison.label.count, 7, "Six digits in two groups: \(comparison.label)")
        captureScreenshot(named: "590-03-comparison-code")
        requireExists(app.buttons["pairMac_button_codesMatch"], message: "They Match").tap()

        requireExists(app.staticTexts["pairMac_label_paired"], timeout: 10, message: "The Mac confirms and the phone pins it")
        captureScreenshot(named: "590-04-paired")
        app.buttons["pairMac_button_done"].tap()

        requireExists(app.staticTexts["pairing_label_pairedMac"], timeout: 5, message: "The sheet shows the paired Mac")
        let pairedRow = requireExists(app.buttons["pairing_row_Test Mac"], message: "The Mac is still listed")
        XCTAssertTrue(pairedRow.label.contains("Paired"), "The row now says Paired: \(pairedRow.label)")
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 8), "The paired link comes up")
        captureScreenshot(named: "590-05-connected")
    }

    func testWrongCodeIsRefused() throws {
        openPairingSheet()
        requireExists(app.buttons["pairing_row_Test Mac"], timeout: 5, message: "The fake Mac should be listed").tap()
        let field = requireExists(app.textFields["pairMac_textfield_code"], timeout: 5, message: "The code field should show")
        field.tap()
        // A well-formed code that isn't the Mac's.
        field.typeText("00000-00000-00000-00000-00000-0")
        app.buttons["pairMac_button_pairWithCode"].tap()
        requireExists(app.staticTexts["pairMac_label_failed"], timeout: 8, message: "The Mac refuses a wrong code")
        XCTAssertFalse(app.staticTexts["pairMac_label_comparisonCode"].exists, "No comparison code without the right secret")
        captureScreenshot(named: "590-06-wrong-code")
    }

    func testPairWithScannedQR() throws {
        openPairingSheet()
        requireExists(app.buttons["pairing_button_pairQR"], timeout: 5, message: "Pair with QR Code").tap()
        requireExists(app.buttons["pairMac_button_scan"], timeout: 5, message: "Scan button").tap()
        requireExists(app.buttons["pairMac_button_simulateScan"], timeout: 5, message: "The simulator stands in for the camera").tap()
        requireExists(app.staticTexts["pairMac_label_comparisonCode"], timeout: 8, message: "The QR pairing reaches the comparison code")
        requireExists(app.buttons["pairMac_button_codesMatch"], message: "They Match").tap()
        requireExists(app.staticTexts["pairMac_label_paired"], timeout: 10, message: "The QR pairing completes")
        captureScreenshot(named: "590-07-paired-by-qr")
    }

    func testCodesDifferSavesNothing() throws {
        openPairingSheet()
        requireExists(app.buttons["pairing_row_Test Mac"], timeout: 5, message: "The fake Mac should be listed").tap()
        let field = requireExists(app.textFields["pairMac_textfield_code"], timeout: 5, message: "The code field should show")
        field.tap()
        field.typeText(Self.code)
        app.buttons["pairMac_button_pairWithCode"].tap()
        requireExists(app.buttons["pairMac_button_codesDiffer"], timeout: 8, message: "Don't Match").tap()
        requireExists(app.staticTexts["pairMac_label_failed"], timeout: 5, message: "Don't Match ends pairing")
        captureScreenshot(named: "590-08-codes-differ")
        app.navigationBars.buttons.firstMatch.tap()
        requireExists(app.buttons["pairing_button_pairQR"], timeout: 5, message: "The phone is still unpaired")
    }

    // MARK: - Helpers

    private func openPairingSheet() {
        requireExists(app.tabBars.buttons["Dashboard"], message: "Dashboard tab should exist").tap()
        let settingsButton = app.buttons["dashboard_button_settings"]
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        } else {
            requireExists(app.navigationBars.buttons.firstMatch, message: "A navigation bar button should exist for settings").tap()
        }
        requireExists(app.byID("screen_settings"), timeout: 8, message: "Settings screen should open")
        let connect = app.buttons["settings_button_connectMac"]
        scrollToElement(connect)
        requireExists(connect, message: "Connect to Mac").tap()
        requireExists(app.byID("screen_macPairing"), timeout: 5, message: "The pairing sheet should open")
    }
}
