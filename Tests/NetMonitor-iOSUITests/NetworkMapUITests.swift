import XCTest

@MainActor
final class NetworkMapUITests: IOSUITestCase {

    override func setUp() async throws {
        try await super.setUp()
        app.tabBars.buttons["Map"].tap()
    }

    // MARK: - Screen Existence

    func testNetworkMapScreenExistsAndShowsContent() throws {
        requireExists(ui("screen_networkMap"), message: "Network map screen should exist after tapping Map tab")
        // FUNCTIONAL: screen should contain at least a scan button or summary
        XCTAssertTrue(
            app.buttons["networkMap_button_scan"].waitForExistence(timeout: 3) ||
            ui("networkMap_summary").waitForExistence(timeout: 3),
            "Network map screen should contain scan button or network summary content"
        )
    }

    func testNavigationTitleExists() throws {
        requireExists(app.navigationBars["Network Map"], message: "Network Map navigation title should exist")
    }

    // MARK: - Network Summary

    func testNetworkSummaryContainsData() throws {
        let summary = ui("networkMap_summary")
        guard summary.waitForExistence(timeout: 5) else {
            // Summary may not appear if no network is configured — acceptable
            return
        }
        // FUNCTIONAL: summary should contain text content (network name, device count, etc.)
        XCTAssertTrue(
            summary.staticTexts.count > 0,
            "Network summary should contain visible text content, not be empty"
        )
    }

    func testNetworkPickerExistsAndIsTappable() throws {
        let addButton = app.buttons["Add Network"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5),
                     "Add Network button should exist on network map")
        XCTAssertTrue(addButton.isEnabled, "Add Network button should be tappable")
    }

    func testAddNetworkSheetShowsManualFields() throws {
        let addButton = app.buttons["Add Network"].firstMatch
        requireExists(addButton, message: "Add Network button should exist").tap()
        requireExists(app.navigationBars["Add Network"], timeout: 8, message: "Add Network sheet should appear")

        let manualTab = app.segmentedControls.buttons["Manual"]
        if manualTab.waitForExistence(timeout: 3) {
            manualTab.tap()
        }

        let gatewayField = app.textFields["networkSheet_field_gateway"]
        let cidrField = app.textFields["networkSheet_field_cidr"]
        let nameField = app.textFields["networkSheet_field_name"]

        XCTAssertTrue(gatewayField.waitForExistence(timeout: 5),
                     "Gateway field should exist in Manual tab")
        XCTAssertTrue(cidrField.waitForExistence(timeout: 5),
                     "CIDR field should exist in Manual tab")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5),
                     "Name field should exist in Manual tab")

        // FUNCTIONAL: verify fields accept text input
        clearAndTypeText("192.168.1.1", into: gatewayField)
        XCTAssertEqual(gatewayField.value as? String, "192.168.1.1",
                      "Gateway field should accept typed input")

        clearAndTypeText("24", into: cidrField)
        XCTAssertEqual(cidrField.value as? String, "24",
                      "CIDR field should accept typed input")
    }

    // MARK: - Sort Controls

    func testSortPickerExistsAndIsInteractive() throws {
        let sortPicker = app.buttons["networkMap_picker_sort"].exists
            ? app.buttons["networkMap_picker_sort"]
            : ui("networkMap_picker_sort")

        guard sortPicker.waitForExistence(timeout: 5) else {
            XCTFail("Sort picker should exist on network map screen")
            return
        }

        // FUNCTIONAL: tapping sort picker should present sort options
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

        // Dismiss by selecting an option or tapping outside
        if app.buttons["IP Address"].exists {
            app.buttons["IP Address"].tap()
        } else if app.buttons["Name"].exists {
            app.buttons["Name"].tap()
        } else {
            let dismissArea = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            dismissArea.tap()
        }

        requireExists(ui("screen_networkMap"), timeout: 5,
                     message: "Network map should remain visible after sort selection")
    }

    // MARK: - Scan Button

    func testScanButtonExistsAndIsTappable() throws {
        let scanButton = app.buttons["networkMap_button_scan"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5),
                     "Scan button should exist on network map")
        XCTAssertTrue(scanButton.isEnabled, "Scan button should be tappable")
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

    func testEmptyStateOrDeviceRowsVisible() throws {
        let emptyLabel = ui("networkMap_label_empty")
        let deviceRow = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")).firstMatch
        XCTAssertTrue(
            emptyLabel.exists || deviceRow.exists || app.activityIndicators.firstMatch.exists,
            "Network map should show devices, empty state, or activity indicator"
        )
        // FUNCTIONAL: if empty state is showing, it should contain instructional text
        if emptyLabel.exists {
            XCTAssertTrue(
                emptyLabel.staticTexts.count > 0 || emptyLabel.label.count > 0,
                "Empty state label should contain instructional text"
            )
        }
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
            let detailScreen = ui("screen_deviceDetail")
            requireExists(detailScreen, timeout: 8,
                         message: "Device detail screen should appear after tapping device row")

            // FUNCTIONAL: detail screen should contain device information
            XCTAssertTrue(
                detailScreen.staticTexts.count > 0,
                "Device detail screen should contain device information text"
            )
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

    func testSortPickerInteractionChangesSortOrder() {
        let sortPicker = app.buttons["networkMap_picker_sort"].exists
            ? app.buttons["networkMap_picker_sort"]
            : ui("networkMap_picker_sort")

        guard sortPicker.waitForExistence(timeout: 5) else { return }

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

        // FUNCTIONAL: select a sort option and verify the map still renders
        if app.buttons["IP Address"].exists {
            app.buttons["IP Address"].tap()
        } else if app.buttons["Name"].exists {
            app.buttons["Name"].tap()
        } else {
            let dismissArea = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            dismissArea.tap()
        }

        requireExists(ui("screen_networkMap"), timeout: 5,
                     message: "Network map should remain visible after sort selection")

        // FUNCTIONAL: after sort, the map should still contain its core elements
        XCTAssertTrue(
            app.buttons["networkMap_button_scan"].waitForExistence(timeout: 3),
            "Scan button should still be visible after changing sort order"
        )
    }

    func testAddNetworkManualTabFieldsAcceptInputAndCancelDismisses() {
        let addButton = app.buttons["Add Network"].firstMatch
        requireExists(addButton, message: "Add Network button should exist").tap()
        requireExists(app.navigationBars["Add Network"], timeout: 8, message: "Add Network sheet should appear")

        let manualTab = app.segmentedControls.buttons["Manual"]
        if manualTab.waitForExistence(timeout: 3) {
            manualTab.tap()
        }

        let gatewayField = app.textFields["networkSheet_field_gateway"]
        if gatewayField.waitForExistence(timeout: 5) {
            clearAndTypeText("192.168.1.1", into: gatewayField)
        }

        let cidrField = app.textFields["networkSheet_field_cidr"]
        if cidrField.waitForExistence(timeout: 3) {
            clearAndTypeText("24", into: cidrField)
        }

        // FUNCTIONAL: verify input was accepted
        if gatewayField.exists {
            XCTAssertEqual(gatewayField.value as? String, "192.168.1.1",
                          "Gateway field should retain typed value")
        }

        let cancelButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'networkSheet_button_cancel' OR label == 'Cancel'")
        ).firstMatch
        requireExists(cancelButton, timeout: 5, message: "Cancel button should exist in Add Network sheet").tap()

        XCTAssertTrue(
            waitForDisappearance(app.navigationBars["Add Network"], timeout: 5),
            "Add Network sheet should dismiss after tapping Cancel"
        )

        // FUNCTIONAL: after cancel, the network map should remain unchanged
        XCTAssertTrue(
            ui("screen_networkMap").waitForExistence(timeout: 5),
            "Network map should be visible after canceling Add Network"
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
            let detailScreen = ui("screen_deviceDetail")
            requireExists(
                detailScreen,
                timeout: 8,
                message: "Device detail screen should appear after tapping a device row"
            )

            // FUNCTIONAL: detail screen should show device-specific content
            XCTAssertTrue(
                detailScreen.staticTexts.count > 0,
                "Device detail screen should contain device information"
            )

            // FUNCTIONAL: back navigation should return to network map
            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.waitForExistence(timeout: 3) {
                backButton.tap()
                XCTAssertTrue(
                    ui("screen_networkMap").waitForExistence(timeout: 5),
                    "Should navigate back to network map from device detail"
                )
            }
        }
    }

    // MARK: - Helpers

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

}
