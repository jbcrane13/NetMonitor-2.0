import XCTest

// MARK: - NetworkDetailViewUITests
//
// Tests for the per-network "war room" dashboard (NetworkDetailView).
// This view is shown when a network profile is selected from the sidebar.
//
// Navigation strategy: the app auto-navigates to the first (local) network
// on launch (see ContentView.onAppear). When no network exists, we create
// one via the "Add Network" sheet before testing the detail view. Both paths
// are covered below.
//
// Accessibility identifiers used (from source):
//   NetworkDetailView wrapper:      "contentView_nav_network"
//   InternetActivityCard:           "dashboard_card_internetActivity"
//   HealthGaugeCard:                "dashboard_card_healthGauge"
//   ISPHealthCard:                  (set by ISPHealthCard internally — see note)
//   LatencyAnalysisCard:            "networkDetail_card_latency"      (wrapper)
//   ConnectivityCard:               "dashboard_card_connectivity"
//   NetworkDevicesPanel:            "networkDetail_section_devices"
//   Range picker (in activity):     "dashboard_activity_rangePicker"
//   Health score text:              "dashboard_healthGauge_score"
//   NetworkDetailView outer wrap:   .accessibilityIdentifier("networkDetail_row_activity")
//                                   .accessibilityIdentifier("networkDetail_row_health")
//
// NOTE: Some cards (ISP, Latency, Connectivity, Intel) carry the accessibility
// identifier added in NetworkDetailView (.accessibilityIdentifier("networkDetail_card_*")).
// These wrap the card's own identifier. Both are present in the hierarchy and
// either can be used to verify presence.

final class NetworkDetailViewUITests: MacOSUITestCase {

    // MARK: - Setup

    /// Add a network and select it so NetworkDetailView is on screen.
    /// Returns without failing if a network is already visible (auto-selected on launch).
    private func ensureNetworkDetailVisible() {
        // The app auto-selects the first network on launch.
        // If detail_network already exists we're done.
        if app.otherElements["contentView_nav_network"].waitForExistence(timeout: 4) {
            return
        }

        // No network selected — add one via the sheet.
        let addButton = app.buttons["sidebar_button_addNetwork"]
        guard addButton.waitForExistence(timeout: 5) else {
            XCTFail("sidebar_button_addNetwork not found — cannot create test network")
            return
        }
        addButton.tap()

        guard app.sheets.firstMatch.waitForExistence(timeout: 3) else {
            XCTFail("Add Network sheet did not appear")
            return
        }

        clearAndTypeText("10.99.0.1", into: app.textFields["addNetwork_textfield_gateway"])
        clearAndTypeText("10.99.0.0/24", into: app.textFields["addNetwork_textfield_subnet"])
        clearAndTypeText("UITest Network", into: app.textFields["addNetwork_textfield_name"])

        let addNetworkButton = app.buttons["addNetwork_button_add"]
        XCTAssertTrue(addNetworkButton.waitForExistence(timeout: 3))
        XCTAssertTrue(addNetworkButton.isEnabled, "Add button should be enabled after valid input")
        addNetworkButton.tap()

        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3),
                      "Add Network sheet should dismiss after confirming")

        // Select the new network item in the sidebar
        let networkItem = app.staticTexts["UITest Network"]
        if networkItem.waitForExistence(timeout: 5) {
            networkItem.tap()
        }

        XCTAssertTrue(app.otherElements["contentView_nav_network"].waitForExistence(timeout: 5),
                      "NetworkDetailView (detail_network) should appear after selecting network")
    }

    // MARK: - Smoke: network detail view exists

    func testNetworkDetailViewAppearsAfterSelectingNetwork() {
        ensureNetworkDetailVisible()
        requireExists(app.otherElements["contentView_nav_network"], timeout: 5,
                      message: "detail_network container should be visible after navigation")
    }

    // MARK: - Row A: Internet Activity Card

    func testInternetActivityCardIsPresent() {
        ensureNetworkDetailVisible()

        // The InternetActivityCard carries both its own identifier and the
        // wrapper identifier added in NetworkDetailView.
        let card = app.otherElements["networkDetail_row_activity"]
        XCTAssertTrue(card.waitForExistence(timeout: 5),
                      "network_detail_row_activity (InternetActivityCard wrapper) should be present")
    }

    func testInternetActivityRangePickerHasThreeSegments() {
        ensureNetworkDetailVisible()

        let picker = app.segmentedControls["dashboard_activity_rangePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "dashboard_activity_rangePicker should exist in the activity card")

        // BandwidthRange has exactly three cases: 24H, 7D, 30D
        XCTAssertEqual(picker.buttons.count, 3,
                       "Range picker should have exactly 3 segments (24H, 7D, 30D)")
    }

    func testInternetActivityRangePickerCanBeChangedTo7D() {
        ensureNetworkDetailVisible()

        let picker = app.segmentedControls["dashboard_activity_rangePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "dashboard_activity_rangePicker should exist")

        let segment7D = picker.buttons["7D"]
        XCTAssertTrue(segment7D.waitForExistence(timeout: 3),
                      "7D segment should exist in the range picker")

        segment7D.tap()

        // After tapping 7D the selected segment value should reflect 7D.
        // On macOS segmented controls, the selected button's value is "1".
        XCTAssertTrue(segment7D.isSelected || segment7D.value as? String == "1",
                      "7D segment should become selected after tapping")
    }

    func testInternetActivityRangePickerCanBeChangedTo30D() {
        ensureNetworkDetailVisible()

        let picker = app.segmentedControls["dashboard_activity_rangePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))

        let segment30D = picker.buttons["30D"]
        XCTAssertTrue(segment30D.waitForExistence(timeout: 3),
                      "30D segment should exist in the range picker")

        segment30D.tap()

        XCTAssertTrue(segment30D.isSelected || segment30D.value as? String == "1",
                      "30D segment should become selected after tapping")
    }

    // MARK: - Row A: Health Gauge Card

    func testHealthGaugeCardIsPresent() {
        ensureNetworkDetailVisible()

        let card = app.otherElements["networkDetail_row_health"]
        XCTAssertTrue(card.waitForExistence(timeout: 5),
                      "network_detail_row_health (HealthGaugeCard wrapper) should be present")
    }

    func testHealthGaugeScoreTextIsVisible() {
        ensureNetworkDetailVisible()

        // dashboard_healthGauge_score is set on the center score Text inside HealthGaugeCard
        let scoreText = app.staticTexts["dashboard_healthGauge_score"]
        XCTAssertTrue(scoreText.waitForExistence(timeout: 5),
                      "dashboard_healthGauge_score should be visible (score or '—')")

        // Value must be a non-empty string (score, dash, or ellipsis while calculating)
        let label = scoreText.label
        XCTAssertFalse(label.isEmpty,
                       "Health gauge score text should not be empty")
    }

    // MARK: - Row B: Left column cards

    func testISPCardIsPresent() {
        ensureNetworkDetailVisible()
        requireExists(app.otherElements["networkDetail_card_isp"], timeout: 5,
                      message: "network_detail_card_isp should be present in the left column")
    }

    func testLatencyAnalysisCardIsPresent() {
        ensureNetworkDetailVisible()
        requireExists(app.otherElements["networkDetail_card_latency"], timeout: 5,
                      message: "network_detail_card_latency should be present in the left column")
    }

    func testConnectivityCardIsPresent() {
        ensureNetworkDetailVisible()
        requireExists(app.otherElements["networkDetail_card_connectivity"], timeout: 5,
                      message: "network_detail_card_connectivity should be present in the left column")
    }

    func testNetworkIntelCardIsPresent() {
        ensureNetworkDetailVisible()
        requireExists(app.otherElements["networkDetail_card_intel"], timeout: 5,
                      message: "network_detail_card_intel should be present in the left column")
    }

    // MARK: - Row B: Right column — NetworkDevicesPanel

    func testNetworkDevicesPanelIsPresent() {
        ensureNetworkDetailVisible()
        requireExists(app.otherElements["networkDetail_section_devices"], timeout: 5,
                      message: "network_detail_panel_devices should be present in the right column")
    }

    func testDevicesPanelShowsEmptyStateOrDeviceList() {
        ensureNetworkDetailVisible()

        // Either the device list or the empty state placeholder should be visible.
        // We accept both: the panel is functional either way.
        let panelList  = app.scrollViews["networkDevicesPanel_list"]
        let panelEmpty = app.otherElements["networkDevicesPanel_label_empty"]

        XCTAssertTrue(
            waitForEither([panelList, panelEmpty], timeout: 5),
            "NetworkDevicesPanel should show either a device list or an empty state"
        )
    }

    // MARK: - Composite: all dashboard cards are reachable

    func testAllDashboardCardsArePresent() {
        ensureNetworkDetailVisible()

        // These identifiers are the wrappers set in NetworkDetailView.
        // They guarantee the structural layout of the "war room" is intact.
        let identifiers: [(id: String, description: String)] = [
            ("networkDetail_row_activity", "InternetActivityCard row wrapper"),
            ("networkDetail_row_health", "HealthGaugeCard row wrapper"),
            ("networkDetail_card_isp", "ISPHealthCard"),
            ("networkDetail_card_latency", "LatencyAnalysisCard"),
            ("networkDetail_card_connectivity", "ConnectivityCard"),
            ("networkDetail_card_intel", "NetworkIntelCard"),
            ("networkDetail_section_devices", "NetworkDevicesPanel"),
        ]

        for item in identifiers {
            XCTAssertTrue(
                app.otherElements[item.id].waitForExistence(timeout: 5),
                "\(item.description) (\(item.id)) should be present in NetworkDetailView"
            )
        }
    }
}
