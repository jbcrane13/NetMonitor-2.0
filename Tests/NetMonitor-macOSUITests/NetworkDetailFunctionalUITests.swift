import XCTest

/// Functional companion tests for NetworkDetailViewUITests.
///
/// Tests verify **outcomes** of interactions with the network detail "war room":
/// device selection, rescan triggers, and device action flows.
/// Existing tests in NetworkDetailViewUITests are NOT modified.
@MainActor
final class NetworkDetailFunctionalUITests: MacOSUITestCase {

    // MARK: - Helpers

    /// Show the local network's live dashboard (the one this Mac is on).
    /// Launch already lands there; ⌘1 re-selects it if something else is showing.
    /// Manual networks show `networkDetail_state_inactiveNetwork` instead of live
    /// cards (#336), so there is no fallback to adding one.
    private func ensureLocalNetworkDetailVisible() {
        if !ui("contentView_nav_network").waitForExistence(timeout: 4) {
            app.typeKey("1", modifierFlags: .command)
        }
        requireExists(ui("contentView_nav_network"), timeout: 5,
                      message: "Network detail should be showing")

        // ⌘1 falls back to the first profile when none is local, so check the layout.
        guard ui("networkDetail_card_isp").waitForExistence(timeout: 5),
              !ui("networkDetail_state_inactiveNetwork").exists else {
            XCTFail("No local network detected — these tests need the live dashboard for this Mac's own network")
            return
        }
    }

    /// First device row in the devices panel. Starts a scan if the panel is empty;
    /// skips when the node's network yields no devices.
    private func firstDeviceRow() throws -> XCUIElement {
        let deviceRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'networkDevicesPanel_row_'")
        ).firstMatch

        if !deviceRow.waitForExistence(timeout: 5) {
            let scanButton = app.buttons["networkDevicesPanel_button_scan"]
            if scanButton.exists, scanButton.isEnabled {
                scanButton.tap()
            }
            guard deviceRow.waitForExistence(timeout: 45) else {
                throw XCTSkip("No devices discovered on this network")
            }
        }
        return deviceRow
    }

    /// macOS 27 exposes SwiftUI Text as `value`, not `label`.
    private func staticText(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).firstMatch
    }

    private func hasText(_ element: XCUIElement) -> Bool {
        !element.label.isEmpty || !((element.value as? String) ?? "").isEmpty
    }

    // MARK: - 1. Click Device in Table -> Device Detail Sheet Opens

    func testClickDeviceRowShowsDeviceInfo() throws {
        ensureLocalNetworkDetailVisible()
        requireExists(ui("networkDetail_section_devices"), timeout: 5, message: "Devices panel should exist")

        let deviceRow = try firstDeviceRow()
        let ip = String(deviceRow.identifier.dropFirst("networkDevicesPanel_row_".count))
        deviceRow.tap()

        requireExists(ui("screen_deviceDetail"), timeout: 5,
                      message: "Clicking a device row should open the device detail sheet")
        XCTAssertTrue(app.sheets.firstMatch.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", ip, ip)
        ).firstMatch.exists, "Device detail should show the selected device's IP \(ip)")

        captureScreenshot(named: "NetworkDetail_DeviceSelected")
    }

    // MARK: - 2. Click Scan Button -> Verify Scan Starts

    func testRescanButtonTriggersScan() {
        ensureLocalNetworkDetailVisible()

        let scanButton = app.buttons["networkDevicesPanel_button_scan"]
        requireExists(scanButton, timeout: 5, message: "Devices panel scan button should exist")
        XCTAssertTrue(scanButton.isEnabled, "Scan button should be enabled before a scan")
        scanButton.tap()

        // While scanning, the button is disabled and a progress overlay is shown.
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"),
                                                 object: scanButton)
        XCTAssertEqual(XCTWaiter().wait(for: [disabled], timeout: 5), .completed,
                       "Scan button should disable while the scan runs")
        XCTAssertTrue(app.progressIndicators.firstMatch.exists,
                      "Devices panel should show scan progress")

        captureScreenshot(named: "NetworkDetail_ScanTriggered")
    }

    // MARK: - 3. Click Device Action (Ping) -> Verify Ping Sheet Opens

    func testDeviceActionPingOpensPingSheetWithIP() throws {
        ensureLocalNetworkDetailVisible()

        let deviceRow = try firstDeviceRow()
        let ip = String(deviceRow.identifier.dropFirst("networkDevicesPanel_row_".count))
        deviceRow.tap()
        requireExists(ui("screen_deviceDetail"), timeout: 5, message: "Device detail sheet should open")

        let pingButton = app.buttons["deviceDetail_button_ping"]
        requireExists(pingButton, timeout: 5, message: "Device detail should offer a Ping action")
        pingButton.tap()

        requireExists(app.buttons["devicePingSheet_button_close"], timeout: 5,
                      message: "Ping action should open the device ping sheet")
        requireExists(staticText("Target:"), timeout: 3, message: "Ping sheet should show its target row")
        XCTAssertTrue(staticText(ip).waitForExistence(timeout: 3),
                      "Ping sheet should target the selected device \(ip)")

        captureScreenshot(named: "NetworkDetail_PingAction")
    }

    // MARK: - 4. Health Gauge Shows Valid Score

    func testHealthGaugeShowsValidScore() {
        ensureLocalNetworkDetailVisible()

        let scoreText = app.staticTexts["healthGauge_label_score"]
        requireExists(scoreText, timeout: 5, message: "Health gauge score should be visible on the local network")

        let label = (scoreText.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? scoreText.label
        // Score is a number, or "—" (no data) / "…" (calculating)
        let isValidScore = label == "\u{2014}" || label == "\u{2026}" || Int(label) != nil
        XCTAssertTrue(isValidScore,
                      "Health gauge should show a numeric score, dash, or placeholder, got: '\(label)'")

        captureScreenshot(named: "NetworkDetail_HealthGauge")
    }

    // MARK: - 5. All Dashboard Cards Present and Responsive

    func testDashboardCardsArePresentAndLayoutIntact() {
        ensureLocalNetworkDetailVisible()

        let requiredCards = [
            "networkDetail_row_health",
            "networkDetail_card_isp",
            "networkDetail_card_latency",
            "networkDetail_card_connectivity",
            "networkDetail_section_devices"
        ]

        var missingCards: [String] = []
        for cardID in requiredCards {
            if !ui(cardID).waitForExistence(timeout: 3) {
                missingCards.append(cardID)
            }
        }

        XCTAssertTrue(missingCards.isEmpty,
                     "Missing dashboard cards: \(missingCards.joined(separator: ", "))")

        // Verify at least one card has real data (not just an empty container)
        // Check ISP card for non-empty label content
        let ispCard = ui("networkDetail_card_isp")
        if ispCard.exists {
            let ispLabels = ispCard.staticTexts
            let hasNonEmptyLabel = ispLabels.allElementsBoundByIndex.contains(where: hasText)
            XCTAssertTrue(hasNonEmptyLabel,
                          "ISP card should display non-empty text content")
        }

        // Check latency card for non-empty label content
        let latencyCard = ui("networkDetail_card_latency")
        if latencyCard.exists {
            let latencyLabels = latencyCard.staticTexts
            let hasNonEmptyLabel = latencyLabels.allElementsBoundByIndex.contains(where: hasText)
            XCTAssertTrue(hasNonEmptyLabel,
                          "Latency card should display non-empty text content")
        }

        // Check connectivity card for non-empty label content
        let connectivityCard = ui("networkDetail_card_connectivity")
        if connectivityCard.exists {
            let connLabels = connectivityCard.staticTexts
            let hasNonEmptyLabel = connLabels.allElementsBoundByIndex.contains(where: hasText)
            XCTAssertTrue(hasNonEmptyLabel,
                          "Connectivity card should display non-empty text content")
        }

        captureScreenshot(named: "NetworkDetail_AllCards")
    }
}
