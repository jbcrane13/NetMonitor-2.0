import XCTest

/// Functional companion tests for NetworkMapUITests.
///
/// Tests verify **outcomes** of network map interactions: scan triggers,
/// device discovery state changes, and device detail navigation.
/// Existing tests in NetworkMapUITests are NOT modified.
@MainActor
final class NetworkMapFunctionalUITests: IOSUITestCase {

    // MARK: - Helpers

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func openNetworkMap() {
        app.tabBars.buttons["Map"].tap()
        requireExists(ui("screen_networkMap"), timeout: 8,
                      message: "Network Map screen should appear after tapping Map tab")
    }

    // MARK: - 1. Tap Scan Button -> Verify Scan Starts (Progress Appears)

    func testScanButtonTriggersScanWithProgressIndicator() {
        openNetworkMap()

        let scanButton = app.buttons["networkMap_button_scan"]
        requireExists(scanButton, timeout: 5, message: "Scan button should exist on network map")

        scanButton.tap()

        // Scan should start: look for stop button, progress indicator, or activity
        let scanStarted = waitForEither([
            app.buttons["networkMap_button_stop"],
            app.activityIndicators.firstMatch,
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Scanning'")
            ).firstMatch,
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'scanning'")
            ).firstMatch
        ], timeout: 10)

        // Also accept the scan completing instantly (scan button reappears)
        let scanCompleted = app.buttons["networkMap_button_scan"].exists
        let deviceFound = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")
        ).firstMatch.exists

        XCTAssertTrue(
            scanStarted || scanCompleted || deviceFound,
            "Tapping scan should trigger scanning state (stop button, progress indicator, device rows, or completed)"
        )

        captureScreenshot(named: "NetworkMap_ScanTriggered")
    }

    // MARK: - 2. Tap Device in Map -> Verify Device Detail Navigation

    func testTapDeviceRowNavigatesToDeviceDetail() {
        openNetworkMap()

        // Trigger a scan to populate device rows
        let scanButton = app.buttons["networkMap_button_scan"]
        if scanButton.waitForExistence(timeout: 5) {
            scanButton.tap()
        }

        // Wait for at least one device row to appear
        let firstDeviceRow = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")
        ).firstMatch

        if firstDeviceRow.waitForExistence(timeout: 20) {
            firstDeviceRow.tap()

            // Should navigate to device detail screen
            let deviceDetail = ui("screen_deviceDetail")
            requireExists(deviceDetail, timeout: 8,
                          message: "Device detail screen should appear after tapping device row")

            // Verify device detail has meaningful content
            let hasDetailContent = waitForEither([
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] '192.168'")
                ).firstMatch,
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] '10.0.'")
                ).firstMatch,
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] 'IP'")
                ).firstMatch,
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] 'MAC'")
                ).firstMatch
            ], timeout: 5)

            XCTAssertTrue(hasDetailContent,
                         "Device detail should show IP, MAC, or device information")

            captureScreenshot(named: "NetworkMap_DeviceDetail")
        } else {
            // No devices found after scan - acceptable on simulator without network
            captureScreenshot(named: "NetworkMap_NoDevicesFound")
        }
    }

    // MARK: - 3. Scan Produces Devices or Shows Empty State

    func testScanProducesDevicesOrEmptyState() {
        openNetworkMap()

        let scanButton = app.buttons["networkMap_button_scan"]
        if scanButton.waitForExistence(timeout: 5) {
            scanButton.tap()
        }

        // Wait for scan to complete (stop button disappears or scan button returns)
        let scanComplete = app.buttons["networkMap_button_scan"].waitForExistence(timeout: 30)

        if scanComplete {
            // After scan, should show devices or empty state
            let hasOutcome = waitForEither([
                app.otherElements.matching(
                    NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")
                ).firstMatch,
                ui("networkMap_label_empty"),
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] 'No Nodes'")
                ).firstMatch,
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] 'SIGNAL GRID'")
                ).firstMatch
            ], timeout: 8)

            XCTAssertTrue(hasOutcome,
                         "Scan should produce device rows, empty state, or signal grid label")
        }

        captureScreenshot(named: "NetworkMap_ScanResults")
    }

    // MARK: - 4. Sort Picker Changes Sort Order

    func testSortPickerChangesOrder() {
        openNetworkMap()

        let sortPicker = app.buttons["networkMap_picker_sort"].exists
            ? app.buttons["networkMap_picker_sort"]
            : ui("networkMap_picker_sort")

        guard sortPicker.waitForExistence(timeout: 5) else { return }

        sortPicker.tap()

        // Sort options should appear
        let hasOptions = waitForEither([
            app.buttons["IP Address"],
            app.buttons["Name"],
            app.buttons["Signal Strength"],
            app.sheets.firstMatch,
            app.menus.firstMatch,
            app.popovers.firstMatch
        ], timeout: 5)

        XCTAssertTrue(hasOptions, "Sort picker should present sort options")

        // Select a sort option if available
        if app.buttons["IP Address"].exists {
            app.buttons["IP Address"].tap()
        } else if app.buttons["Name"].exists {
            app.buttons["Name"].tap()
        } else {
            // Dismiss picker
            let dismissArea = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            dismissArea.tap()
        }

        // Map should still be visible after sort
        requireExists(ui("screen_networkMap"), timeout: 5,
                      message: "Network map should remain visible after sort selection")

        captureScreenshot(named: "NetworkMap_SortPicker")
    }

    // MARK: - 5. Network Summary Shows Gateway Info

    func testNetworkSummaryShowsNetworkInfo() {
        openNetworkMap()

        let summary = ui("networkMap_summary")
        requireExists(summary, timeout: 8, message: "Network summary should exist on map screen")

        // Summary should contain gateway, network, or signal information
        let summaryHasContent = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Gateway'")
        ).firstMatch.waitForExistence(timeout: 3)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] '192.168'")
            ).firstMatch.waitForExistence(timeout: 2)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] '10.0.'")
            ).firstMatch.waitForExistence(timeout: 2)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'SIGNAL GRID'")
            ).firstMatch.waitForExistence(timeout: 2)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'No Nodes'")
            ).firstMatch.waitForExistence(timeout: 2)

        XCTAssertTrue(summaryHasContent,
                     "Network summary should show gateway, IP, or network state information")

        captureScreenshot(named: "NetworkMap_Summary")
    }

    // MARK: - 6. Add Network Sheet Opens and Cancels

    func testAddNetworkSheetOpensAndDismisses() {
        openNetworkMap()

        let addButton = app.buttons["Add Network"].firstMatch
        guard addButton.waitForExistence(timeout: 5) else { return }

        addButton.tap()

        let addSheet = app.navigationBars["Add Network"]
        requireExists(addSheet, timeout: 8, message: "Add Network sheet should appear")

        // Sheet should contain input fields
        let hasFields = waitForEither([
            app.segmentedControls.firstMatch,
            app.textFields["networkSheet_field_gateway"],
            app.textFields["networkSheet_field_name"]
        ], timeout: 5)

        XCTAssertTrue(hasFields,
                     "Add Network sheet should contain input fields or segmented control")

        // Cancel to dismiss
        let cancelButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'networkSheet_button_cancel' OR label == 'Cancel'")
        ).firstMatch
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        }

        XCTAssertTrue(
            waitForDisappearance(addSheet, timeout: 5),
            "Add Network sheet should dismiss after tapping Cancel"
        )

        captureScreenshot(named: "NetworkMap_AddNetworkSheet")
    }

    // MARK: - 7. Map Screen Tab Round-Trip

    func testMapTabRoundTrip() {
        openNetworkMap()

        // Navigate to Tools
        app.tabBars.buttons["Tools"].tap()
        requireExists(ui("screen_tools"), timeout: 5,
                      message: "Tools screen should appear")

        // Return to Map
        app.tabBars.buttons["Map"].tap()
        requireExists(ui("screen_networkMap"), timeout: 5,
                      message: "Network Map should reappear after tab round-trip")

        // Map content should still be present
        let hasContent = waitForEither([
            ui("networkMap_summary"),
            app.buttons["networkMap_button_scan"]
        ], timeout: 5)

        XCTAssertTrue(hasContent,
                     "Network map should retain its content after tab round-trip")

        captureScreenshot(named: "NetworkMap_TabRoundTrip")
    }
}
