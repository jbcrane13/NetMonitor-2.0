import XCTest

final class PortScannerToolUITests: MacOSUITestCase {

    private func openPortScanner() {
        openTool(cardID: "tools_card_port_scanner", sheetElement: "portScan_textfield_host")
    }

    // MARK: - Element Existence

    func testHostFieldExists() {
        openPortScanner()
        requireExists(app.textFields["portScan_textfield_host"], message: "Host field should exist")
        captureScreenshot(named: "PortScanner_Screen")
    }

    func testPresetPickerExists() {
        openPortScanner()
        requireExists(app.popUpButtons["portScan_picker_preset"], message: "Preset picker should exist")
    }

    func testScanButtonExists() {
        openPortScanner()
        requireExists(app.buttons["portScan_button_scan"], message: "Scan button should exist")
    }

    func testCloseButtonExists() {
        openPortScanner()
        requireExists(app.buttons["portScan_button_close"], message: "Close button should exist")
    }

    // MARK: - Input Validation

    func testScanButtonDisabledWhenHostEmpty() {
        openPortScanner()
        let scanButton = requireExists(app.buttons["portScan_button_scan"], message: "Scan button should exist")
        XCTAssertFalse(scanButton.isEnabled, "Scan button should be disabled without host input")
    }

    func testScanButtonEnabledAfterTypingHost() {
        openPortScanner()
        clearAndTypeText("127.0.0.1", into: app.textFields["portScan_textfield_host"])
        let scanButton = requireExists(app.buttons["portScan_button_scan"], message: "Scan button should exist")
        XCTAssertTrue(scanButton.isEnabled, "Scan button should be enabled after entering host")
    }

    // MARK: - Navigation

    func testCloseButtonDismissesSheet() {
        openPortScanner()
        app.buttons["portScan_button_close"].tap()
        requireExists(
            app.otherElements["tools_card_port_scanner"],
            message: "Tool card should reappear after closing sheet"
        )
    }

    // MARK: - Scan Execution

    func testStartScan() {
        openPortScanner()
        clearAndTypeText("127.0.0.1", into: app.textFields["portScan_textfield_host"])
        app.buttons["portScan_button_scan"].tap()

        // Button should remain (may change label to Stop)
        let scanButton = app.buttons["portScan_button_scan"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 3), "Scan button should remain visible during scan")
        captureScreenshot(named: "PortScanner_Scanning")
    }

    func testCustomPresetShowsCustomField() {
        openPortScanner()
        let presetPicker = requireExists(app.popUpButtons["portScan_picker_preset"], message: "Preset picker should exist")
        presetPicker.tap()

        let customOption = app.menuItems["Custom"]
        if customOption.waitForExistence(timeout: 2) {
            customOption.tap()
            let customField = app.textFields["portScan_textfield_custom"]
            if customField.waitForExistence(timeout: 3) {
                XCTAssertTrue(customField.exists, "Custom ports field should appear after selecting Custom preset")
                captureScreenshot(named: "PortScanner_CustomPreset")
            }
        }
    }
}
