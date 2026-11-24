import XCTest

/// User flow for #456: from device detail, Scan Label reads the label in a photo and shows
/// its fields for review; Save keeps them on the device.
///
/// The simulator has no camera, so `UITEST_LABEL_IMAGE=1` gives the sheet a drawn label
/// (Northwind Networks NW-AC1200, S/N NW12K4471093, MAC 00:1E:42:7A:9C:31) that real Vision
/// OCR reads. `UITEST_LABEL_MODEL=answer` stands in for the on-device model, and its answer
/// is still checked against the OCR text; `unavailable` turns the model off.
@MainActor
class LabelCaptureUITestCase: IOSUITestCase {
    var labelModel: String { "answer" }

    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_LABEL_IMAGE": "1", "UITEST_LABEL_MODEL": labelModel]
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func openFirstDeviceAndScanLabel() {
        let devicesCard = element("dashboard_card_localDevices")
        scrollToElement(devicesCard)
        requireExists(devicesCard, timeout: 10, message: "Local devices card should exist on dashboard")
        devicesCard.tap()

        let firstDeviceRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'deviceList_row_device_'")
        ).firstMatch
        requireExists(firstDeviceRow, timeout: 8, message: "Fake device feed should list a device")
        firstDeviceRow.tap()
        requireExists(element("screen_deviceDetail"), timeout: 5, message: "Device detail should open")

        let scanLabel = element("deviceDetail_button_scanLabel")
        scrollToElement(scanLabel)
        requireExists(scanLabel, timeout: 5, message: "Device detail should offer Scan Label")
        scanLabel.tap()
    }

    /// The text field's current value.
    func value(of identifier: String) -> String {
        (element(identifier).value as? String) ?? ""
    }
}

final class LabelCaptureUITests: LabelCaptureUITestCase {
    func testScanLabelFillsTheFieldsAndSaveKeepsTheModel() throws {
        openFirstDeviceAndScanLabel()

        // OCR starts cold in a fresh simulator (about half a minute on a Mac).
        let save = element("labelCapture_button_save")
        requireExists(save, timeout: 90, message: "The review sheet should open with the label's fields")
        XCTAssertEqual(value(of: "labelCapture_field_model"), "NW-AC1200")
        XCTAssertEqual(value(of: "labelCapture_field_mac"), "00:1E:42:7A:9C:31")
        XCTAssertEqual(value(of: "labelCapture_field_serial"), "NW12K4471093")
        XCTAssertTrue(element("labelCapture_field_model_generated").exists, "Model-filled fields should be marked")
        captureScreenshot(named: "LabelCapture_Review")

        save.tap()
        XCTAssertTrue(waitForDisappearance(save, timeout: 5), "Save should close the sheet")
        let model = element("deviceDetail_row_model")
        scrollToElement(model)
        requireExists(model, timeout: 5, message: "Device detail should show the saved model")
        XCTAssertTrue(app.staticTexts["NW-AC1200"].exists, "The captured model should be shown")
        XCTAssertTrue(app.staticTexts["Northwind Networks"].exists, "The captured maker should be shown")
        captureScreenshot(named: "LabelCapture_SavedModel")
    }
}

final class LabelCaptureWithoutModelUITests: LabelCaptureUITestCase {
    override var labelModel: String { "unavailable" }

    func testWithoutTheModelTheAppReadsTheMAC() throws {
        openFirstDeviceAndScanLabel()

        let save = element("labelCapture_button_save")
        requireExists(save, timeout: 90, message: "The review sheet should open without the model")
        XCTAssertEqual(value(of: "labelCapture_field_mac"), "00:1E:42:7A:9C:31")
        XCTAssertEqual(value(of: "labelCapture_field_serial"), "NW12K4471093")
        XCTAssertFalse(element("labelCapture_field_mac_generated").exists, "Nothing should be marked as model-filled")
        captureScreenshot(named: "LabelCapture_NoModel_Review")
    }
}
