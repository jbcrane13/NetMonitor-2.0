import XCTest

/// #594 PR1 user flow: a device saved as two interfaces is one device. `UITEST_SEED_DEVICE_GROUP=1`
/// saves "UITest Studio Mac": a wired primary at 192.168.1.60 (offline, not in the UI-test scan,
/// notes "Wired port in the studio") grouped with 192.168.1.13, which is the UI-test scan's
/// uitest-device-3 (notes "Wi-Fi interface"). After a scan only 192.168.1.13 answered. Fixture
/// names only; screenshots cropped to the element.
@MainActor
final class DeviceGroupUITests: PresenceUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_SCAN_CLOCK": "1", "UITEST_SEED_DEVICE_GROUP": "1"]
    }

    private let deviceName = "UITest Studio Mac"

    func testADeviceWithTwoInterfacesIsOneDeviceOnlineWhileEitherAnswers() {
        scan()
        openDeviceList()

        // One row, at the interface that answered, with the primary's name, online.
        let device = row("192.168.1.13")
        requireExists(device, timeout: 10, message: "The list should show the device at its answering interface")
        expectValue(device, startsWith: "Online", "The device is online while its other interface answers")
        XCTAssertTrue(device.label.contains(deviceName) || device.staticTexts[deviceName].exists, "The row is named by the primary: \(device.label)")
        XCTAssertFalse(row("192.168.1.60").exists, "The wired interface is not a second device")
        XCTAssertLessThanOrEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", deviceName)).count, 1, "The device is listed once")
        keepCroppedEvidence(device, named: "594-ios-one-device-online")

        // Detail: both interfaces, and both members' notes.
        device.tap()
        let interfaces = ui("deviceDetail_section_interfaces")
        scrollToElement(interfaces)
        requireExists(interfaces, timeout: 8, message: "Detail should list the device's interfaces")
        XCTAssertTrue(ui("deviceDetail_row_interface_192_168_1_13").exists, "The Wi-Fi interface is listed")
        XCTAssertTrue(ui("deviceDetail_row_interface_192_168_1_60").exists, "The wired interface is listed")
        let memberNotes = ui("deviceDetail_textfield_interfaceNotes_192_168_1_13")
        requireExists(memberNotes, timeout: 5, message: "The Wi-Fi interface's notes are on its row")
        XCTAssertEqual(value(memberNotes), "Wi-Fi interface")
        keepCroppedEvidence(interfaces, named: "594-ios-detail-interfaces")

        let notes = ui("deviceDetail_textfield_notes")
        scrollToElement(notes)
        requireExists(notes, timeout: 5, message: "The primary's notes stay in Notes")
        XCTAssertEqual(value(notes), "Wired port in the studio")
        XCTAssertEqual(ui("deviceDetail_label_notesInterface").label, "192.168.1.60", "The notes say which interface they're about")
        keepCroppedEvidence(ui("deviceDetail_label_notesTitle"), named: "594-ios-detail-notes-title")
        keepCroppedEvidence(notes, named: "594-ios-detail-primary-notes")

        // Remove the wired interface: it has a name and notes, so the app asks first.
        let remove = ui("deviceDetail_button_removeInterface_192_168_1_60")
        scrollToElement(remove)
        requireExists(remove, timeout: 5, message: "Each interface offers Remove this interface").tap()
        let confirm = app.buttons["Remove Interface"].firstMatch
        requireExists(confirm, timeout: 5, message: "Removing an interface with notes asks first")
        keepCroppedEvidence(app.sheets.firstMatch.exists ? app.sheets.firstMatch : confirm, named: "594-ios-remove-confirmation")
        confirm.tap()

        XCTAssertTrue(waitForDisappearance(interfaces, timeout: 5), "One interface left: no Interfaces section")
        let address = ui("deviceDetail_row_ipAddress")
        app.swipeDown()
        app.swipeDown()
        requireExists(address, timeout: 5, message: "Detail stays open on the remaining interface")
        XCTAssertTrue(address.label.contains("192.168.1.13") || value(address).contains("192.168.1.13") ||
            app.staticTexts["192.168.1.13"].exists, "Detail shows the remaining interface")

        app.navigationBars.buttons.firstMatch.tap()
        let remaining = row("192.168.1.13")
        requireExists(remaining, timeout: 8, message: "The remaining interface is still one device")
        XCTAssertFalse(row("192.168.1.60").exists, "The removed interface is gone")
        keepCroppedEvidence(remaining, named: "594-ios-after-remove")
    }
}
