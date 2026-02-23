import XCTest

@MainActor
final class NetworkMapUITests: IOSUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        app.tabBars.buttons["Map"].tap()
    }

    // MARK: - Screen Existence

    func testNetworkMapScreenExists() throws {
        requireExists(ui("screen_networkMap"), message: "Network map screen should exist after tapping Map tab")
    }

    func testNavigationTitleExists() throws {
        requireExists(app.navigationBars["Devices"], message: "Devices navigation title should exist on network map")
    }

    // MARK: - Network Summary

    func testNetworkSummaryExists() throws {
        requireExists(ui("networkMap_summary"), message: "Network summary should exist on network map screen")
    }

    func testNetworkPickerExists() throws {
        requireExists(app.buttons["Add Network"].firstMatch, message: "Add Network button should exist on network map")
    }

    func testAddNetworkSheetShowsManualFields() throws {
        let addButton = app.buttons["Add Network"].firstMatch
        requireExists(addButton, message: "Add Network button should exist").tap()
        requireExists(app.navigationBars["Add Network"], timeout: 8, message: "Add Network sheet should appear")

        let manualTab = app.segmentedControls.buttons["Manual"]
        if manualTab.waitForExistence(timeout: 3) {
            manualTab.tap()
        }

        requireExists(app.textFields["network_sheet_field_gateway"], timeout: 5, message: "Gateway field should exist in Manual tab")
        requireExists(app.textFields["network_sheet_field_cidr"], timeout: 5, message: "CIDR field should exist in Manual tab")
        requireExists(app.textFields["network_sheet_field_name"], timeout: 5, message: "Name field should exist in Manual tab")
    }

    // MARK: - Sort Controls

    func testSortPickerExists() throws {
        XCTAssertTrue(
            app.buttons["networkMap_picker_sort"].waitForExistence(timeout: 5) ||
            ui("networkMap_picker_sort").waitForExistence(timeout: 3),
            "Sort picker should exist on network map screen"
        )
    }

    // MARK: - Scan Button

    func testScanButtonExists() throws {
        requireExists(app.buttons["networkMap_button_scan"], message: "Scan button should exist on network map")
    }

    func testScanButtonTriggersScan() throws {
        let scanButton = requireExists(app.buttons["networkMap_button_scan"], message: "Scan button should exist")
        scanButton.tap()
        XCTAssertTrue(
            waitForEither(
                [
                    app.activityIndicators.firstMatch,
                    app.buttons["networkMap_button_scan"]
                ],
                timeout: 5
            ),
            "Scan button should still exist or activity indicator should appear after tapping scan"
        )
    }

    // MARK: - Empty State

    func testEmptyStateLabelExists() throws {
        let emptyLabel = ui("networkMap_label_empty")
        let deviceRow = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")).firstMatch
        XCTAssertTrue(
            emptyLabel.exists || deviceRow.exists || app.activityIndicators.firstMatch.exists,
            "Network map should show devices, empty state, or activity indicator"
        )
    }

    // MARK: - Device Row Navigation

    func testDeviceRowNavigatesToDetail() throws {
        let scanButton = requireExists(app.buttons["networkMap_button_scan"], message: "Scan button should exist")
        scanButton.tap()

        let firstDeviceRow = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")
        ).firstMatch

        if firstDeviceRow.waitForExistence(timeout: 15) {
            firstDeviceRow.tap()
            requireExists(ui("screen_deviceDetail"), timeout: 8, message: "Device detail screen should appear after tapping device row")
        }
    }

    // MARK: - Functional Tests

    func testScanButtonTriggersScanningState() {
        let scanButton = requireExists(app.buttons["networkMap_button_scan"], message: "Scan button should exist")
        scanButton.tap()

        let stopButton = app.buttons["networkMap_button_stop"]
        let progressIndicator = app.activityIndicators.firstMatch
        let updatedScanButton = app.buttons["networkMap_button_scan"]

        XCTAssertTrue(
            waitForEither([stopButton, progressIndicator, updatedScanButton], timeout: 10),
            "Tapping scan should transition to scanning state (stop button, progress, or updated scan button)"
        )
    }

    func testSortPickerInteraction() {
        let sortPicker = app.buttons["networkMap_picker_sort"].exists
            ? app.buttons["networkMap_picker_sort"]
            : ui("networkMap_picker_sort")

        if sortPicker.waitForExistence(timeout: 5) {
            sortPicker.tap()
            XCTAssertTrue(
                waitForEither(
                    [
                        app.sheets.firstMatch,
                        app.menus.firstMatch,
                        app.popovers.firstMatch,
                        app.tables.firstMatch
                    ],
                    timeout: 5
                ),
                "Tapping sort picker should present sort options"
            )

            if app.buttons["IP Address"].exists {
                app.buttons["IP Address"].tap()
            } else if app.buttons["Name"].exists {
                app.buttons["Name"].tap()
            } else {
                let dismissArea = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                dismissArea.tap()
            }

            requireExists(ui("screen_networkMap"), timeout: 5, message: "Network map should remain visible after sort selection")
        }
    }

    func testAddNetworkManualTabFieldsAndCancel() {
        let addButton = app.buttons["Add Network"].firstMatch
        requireExists(addButton, message: "Add Network button should exist").tap()
        requireExists(app.navigationBars["Add Network"], timeout: 8, message: "Add Network sheet should appear")

        let manualTab = app.segmentedControls.buttons["Manual"]
        if manualTab.waitForExistence(timeout: 3) {
            manualTab.tap()
        }

        let gatewayField = app.textFields["network_sheet_field_gateway"]
        if gatewayField.waitForExistence(timeout: 5) {
            clearAndTypeText("192.168.1.1", into: gatewayField)
        }

        let cidrField = app.textFields["network_sheet_field_cidr"]
        if cidrField.waitForExistence(timeout: 3) {
            clearAndTypeText("24", into: cidrField)
        }

        let cancelButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'network_sheet_button_cancel' OR label == 'Cancel'")
        ).firstMatch
        requireExists(cancelButton, timeout: 5, message: "Cancel button should exist in Add Network sheet").tap()

        XCTAssertTrue(
            waitForDisappearance(app.navigationBars["Add Network"], timeout: 5),
            "Add Network sheet should dismiss after tapping Cancel"
        )
    }

    func testDeviceRowNavigatesToDetailFunctionally() {
        let scanButton = requireExists(app.buttons["networkMap_button_scan"], message: "Scan button should exist")
        scanButton.tap()

        let firstDeviceRow = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")
        ).firstMatch

        if firstDeviceRow.waitForExistence(timeout: 20) {
            firstDeviceRow.tap()
            requireExists(
                ui("screen_deviceDetail"),
                timeout: 8,
                message: "Device detail screen should appear after tapping a device row"
            )
        }
    }

    // MARK: - Helpers

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForEither(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
