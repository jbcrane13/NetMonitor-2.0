import XCTest

/// #594 PR2 user flows on iPhone: interfaces become one device automatically, by suggestion, or by
/// hand, and come apart again. Fixture names only; screenshots cropped to the element.
///
/// - `UITEST_FAKE_BONJOUR_GROUP=1`: the UI-test scan also finds uitest-studio at 192.168.1.70 and
///   192.168.1.71, each with its own MAC, both answering for `uitest-studio.local`.
/// - `UITEST_SEED_GROUP_SUGGESTION=1`: two saved devices, uitest-library-wired (192.168.1.80) and
///   uitest-library-wifi (192.168.1.81), that answered for `uitest-library.local` an hour ago.
@MainActor
final class DeviceGroupPR2UITests: PresenceUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1", "UITEST_FAKE_BONJOUR_GROUP": "1", "UITEST_SEED_GROUP_SUGGESTION": "1"]
    }

    func testAScanGroupsTwoAddressesThatClaimOneBonjourNameAndSaysSo() {
        scan()
        openDeviceList()

        // One device, at the lower address of the two that answered together.
        let device = row("192.168.1.70")
        requireExists(device, timeout: 10, message: "The list should show the grouped device")
        XCTAssertFalse(row("192.168.1.71").exists, "The second address is not a second device")
        keepCroppedEvidence(device, named: "594-pr2-ios-automatic-one-device")

        device.tap()
        let interfaces = ui("deviceDetail_section_interfaces")
        scrollToElement(interfaces)
        requireExists(interfaces, timeout: 8, message: "Detail should list both interfaces")
        for key in ["192_168_1_70", "192_168_1_71"] {
            let label = ui("deviceDetail_label_groupedByBonjour_\(key)")
            scrollToElement(label)
            requireExists(label, timeout: 5, message: "Interface \(key) should say it was grouped by its Bonjour name")
            XCTAssertEqual(label.label, "Grouped by Bonjour name")
        }
        let wiredRow = ui("deviceDetail_row_interface_192_168_1_71")
        let label = ui("deviceDetail_label_groupedByBonjour_192_168_1_71")
        keepCroppedEvidence(frame: wiredRow.frame.union(label.frame), named: "594-pr2-ios-grouped-by-bonjour")
    }

    func testASuggestionGroupsTwoDevicesAndUndoSeparatesThem() {
        scan()
        openDeviceList()
        requireExists(row("192.168.1.81"), timeout: 10, message: "The Wi-Fi interface is its own device")
        let wired = row("192.168.1.80")
        requireExists(wired, timeout: 5, message: "The wired interface is its own device").tap()

        let banner = ui("deviceDetail_banner_suggestion")
        requireExists(banner, timeout: 8, message: "Detail should suggest the device with the same Bonjour name")
        XCTAssertTrue(
            ui("deviceDetail_label_suggestion").label.contains("uitest-library-wifi"),
            "The banner names the other device: \(ui("deviceDetail_label_suggestion").label)"
        )
        keepCroppedEvidence(banner, named: "594-pr2-ios-suggestion-banner")

        ui("deviceDetail_button_suggestionSameDevice").tap()
        let toast = ui("deviceDetail_label_toastMessage")
        requireExists(toast, timeout: 5, message: "Grouping shows an undo toast")
        XCTAssertEqual(toast.label, "Grouped with uitest-library-wifi")
        XCTAssertTrue(waitForDisappearance(banner, timeout: 5), "The suggestion goes once accepted")
        keepCroppedEvidence(frame: toast.frame.union(ui("deviceDetail_button_dismissToast").frame), named: "594-pr2-ios-undo-toast")
        let interfaces = ui("deviceDetail_section_interfaces")
        scrollToElement(interfaces)
        requireExists(interfaces, timeout: 5, message: "One device with both interfaces")
        XCTAssertTrue(ui("deviceDetail_row_interface_192_168_1_81").exists)

        ui("deviceDetail_button_undo").tap()
        XCTAssertTrue(waitForDisappearance(interfaces, timeout: 5), "Undo makes two devices again")
        XCTAssertTrue(waitForDisappearance(toast, timeout: 5), "The toast goes after Undo")
        app.swipeDown()
        app.swipeDown()
        requireExists(banner, timeout: 5, message: "Undo brings the suggestion back")

        app.navigationBars.buttons.firstMatch.tap()
        requireExists(row("192.168.1.80"), timeout: 8, message: "Two devices again: the wired one")
        let wifi = row("192.168.1.81")
        requireExists(wifi, timeout: 5, message: "Two devices again: the Wi-Fi one")
        scrollToElement(wifi)
        keepCroppedEvidence(wifi, named: "594-pr2-ios-after-undo")
    }

    func testSameDeviceAsThenNotTheSameDevice() {
        scan()
        openDeviceList()
        let first = row("192.168.1.11")
        requireExists(first, timeout: 10, message: "uitest-device-1 should be listed").tap()

        let sameDeviceAs = ui("deviceDetail_button_sameDeviceAs")
        scrollToElement(sameDeviceAs)
        requireExists(sameDeviceAs, timeout: 8, message: "Detail offers Same device as…")
        keepCroppedEvidence(sameDeviceAs, named: "594-pr2-ios-same-device-as-button")
        sameDeviceAs.tap()

        requireExists(ui("screen_sameDeviceAs"), timeout: 5, message: "The picker opens")
        let search = app.searchFields.firstMatch
        requireExists(search, timeout: 5, message: "The picker has search").tap()
        search.typeText("1.12")
        let pick = ui("sameDeviceAs_row_192_168_1_12")
        requireExists(pick, timeout: 5, message: "Search finds uitest-device-2 by its address")
        XCTAssertFalse(ui("sameDeviceAs_row_192_168_1_13").exists, "Search leaves out the others")
        keepCroppedEvidence(pick, named: "594-pr2-ios-picker-search")
        pick.tap()

        requireExists(ui("deviceDetail_label_toastMessage"), timeout: 5, message: "Grouping shows an undo toast")
        XCTAssertEqual(ui("deviceDetail_label_toastMessage").label, "Grouped with uitest-device-2")
        app.navigationBars.buttons.firstMatch.tap()
        let grouped = row("192.168.1.11")
        requireExists(grouped, timeout: 8, message: "One device")
        XCTAssertFalse(row("192.168.1.12").exists, "uitest-device-2 is now an interface of the same device")
        keepCroppedEvidence(grouped, named: "594-pr2-ios-manual-one-device")

        grouped.tap()
        let separate = ui("deviceDetail_button_notSameDevice_192_168_1_12")
        scrollToElement(separate)
        requireExists(separate, timeout: 8, message: "Each interface offers Not the same device")
        keepCroppedEvidence(separate, named: "594-pr2-ios-not-same-device-button")
        separate.tap()
        let toast = ui("deviceDetail_label_toastMessage")
        requireExists(toast, timeout: 5, message: "Separating shows an undo toast")
        XCTAssertEqual(toast.label, "192.168.1.12 is a separate device")
        keepCroppedEvidence(frame: toast.frame.union(ui("deviceDetail_button_dismissToast").frame), named: "594-pr2-ios-separate-toast")
        XCTAssertTrue(waitForDisappearance(ui("deviceDetail_section_interfaces"), timeout: 5), "One interface left")

        app.navigationBars.buttons.firstMatch.tap()
        requireExists(row("192.168.1.11"), timeout: 8, message: "Two devices again: uitest-device-1")
        let second = row("192.168.1.12")
        requireExists(second, timeout: 5, message: "Two devices again: uitest-device-2")
        scrollToElement(second)
        keepCroppedEvidence(second, named: "594-pr2-ios-after-not-same-device")
    }

    /// Keeps the screenshot cropped to `frame`, such as an interface row and its label together.
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
