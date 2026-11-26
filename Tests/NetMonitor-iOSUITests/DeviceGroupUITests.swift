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

        // Detail: the serial (#561), both interfaces, and both members' notes.
        device.tap()
        let serial = ui("deviceDetail_row_serial")
        scrollToElement(serial)
        requireExists(serial, timeout: 8, message: "Detail should show the device's serial number")
        let serialValue = app.staticTexts.matching(identifier: "deviceDetail_row_serial")
            .matching(NSPredicate(format: "label != %@", "Serial Number")).firstMatch
        XCTAssertEqual(serialValue.label, "UITESTSERIAL594", "The primary's serial is shown")
        moveAboveTabBar(serial)
        keepCroppedEvidence(frame: serial.frame.union(serialValue.frame), named: "594-ios-detail-serial")

        let interfaces = ui("deviceDetail_section_interfaces")
        scrollToElement(interfaces)
        requireExists(interfaces, timeout: 8, message: "Detail should list the device's interfaces")
        XCTAssertTrue(ui("deviceDetail_row_interface_192_168_1_13").exists, "The Wi-Fi interface is listed")
        XCTAssertTrue(ui("deviceDetail_row_interface_192_168_1_60").exists, "The wired interface is listed")
        let memberNotes = ui("deviceDetail_textfield_interfaceNotes_192_168_1_13")
        requireExists(memberNotes, timeout: 5, message: "The Wi-Fi interface's notes are on its row")
        XCTAssertEqual(value(memberNotes), "Wi-Fi interface")
        let wifiRow = ui("deviceDetail_row_interface_192_168_1_13")
        moveAboveTabBar(memberNotes)
        keepCroppedEvidence(wifiRow, named: "594-ios-detail-interface-wifi")
        keepCroppedEvidence(memberNotes, named: "594-ios-detail-interface-wifi-notes")
        let wiredRow = ui("deviceDetail_row_interface_192_168_1_60")
        moveAboveTabBar(wiredRow)
        keepCroppedEvidence(wiredRow, named: "594-ios-detail-interface-wired")

        let notes = ui("deviceDetail_textfield_notes")
        scrollToElement(notes)
        requireExists(notes, timeout: 5, message: "The primary's notes stay in Notes")
        XCTAssertEqual(value(notes), "Wired port in the studio")
        XCTAssertEqual(ui("deviceDetail_label_notesInterface").label, "192.168.1.60", "The notes say which interface they're about")
        moveAboveTabBar(notes)
        keepCroppedEvidence(ui("deviceDetail_label_notesInterface"), named: "594-ios-detail-notes-interface")
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

    /// Scrolls until `element` sits in the top half, clear of the floating tab bar, for its screenshot.
    private func moveAboveTabBar(_ element: XCUIElement) {
        let limit = app.windows.firstMatch.frame.height * 0.55
        for _ in 0 ..< 4 where element.frame.maxY > limit {
            app.swipeUp(velocity: .slow)
        }
    }

    /// Keeps the screenshot cropped to `frame`, such as an info row's label and value together.
    private func keepCroppedEvidence(frame: CGRect, named name: String) {
        let image = app.screenshot().image
        let box = frame.insetBy(dx: -8, dy: -8)
        let pixels = CGRect(x: box.minX * image.scale, y: box.minY * image.scale, width: box.width * image.scale, height: box.height * image.scale)
        guard let cropped = image.cgImage?.cropping(to: pixels) else {
            XCTFail("Could not crop \(name)")
            return
        }
        let attachment = XCTAttachment(image: UIImage(cgImage: cropped, scale: image.scale, orientation: .up))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
