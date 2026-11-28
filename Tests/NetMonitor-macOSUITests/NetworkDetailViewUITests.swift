import XCTest

// MARK: - NetworkDetailViewUITests
//
// Tests for the per-network "war room" dashboard (NetworkDetailView).
// This view is shown when a network profile is selected from the sidebar.
//
// Navigation strategy: the app auto-navigates to the first (local) network
// on launch (see ContentView.onAppear), and every test relies on that. Adding
// and selecting a network is covered by NetworkSwitchingUITests.
//
// Accessibility identifiers used (from source):
//   NetworkDetailView wrapper:      "contentView_nav_network"
//   HealthGaugeCard:                "dashboard_card_healthGauge"
//   ISPHealthCard:                  (set by ISPHealthCard internally — see note)
//   LatencyAnalysisCard:            "networkDetail_card_latency"      (wrapper)
//   ConnectivityCard:               "dashboard_card_connectivity"
//   NetworkDevicesPanel:            "networkDetail_section_devices"
//   Health score text:              "healthGauge_label_score"
//   NetworkDetailView outer wrap:   .accessibilityIdentifier("networkDetail_row_health")
//
// NOTE: Some cards (ISP, Latency, Connectivity, Intel) carry the accessibility
// identifier added in NetworkDetailView (.accessibilityIdentifier("networkDetail_card_*")).
// These wrap the card's own identifier. Both are present in the hierarchy and
// either can be used to verify presence.

@MainActor
final class NetworkDetailViewUITests: MacOSUITestCase {

    // MARK: - Setup

    /// The app selects the Mac's own network on launch, so NetworkDetailView
    /// should already be on screen. Fails loudly when it is not.
    private func ensureNetworkDetailVisible() {
        requireExists(ui("contentView_nav_network").firstMatch, timeout: 5,
                      message: "The app should open on the active network's detail view (contentView_nav_network)")
    }

    // MARK: - Smoke: network detail view exists

    func testNetworkDetailViewAppearsAfterSelectingNetwork() {
        ensureNetworkDetailVisible()
        requireExists(ui("contentView_nav_network").firstMatch, timeout: 5,
                      message: "detail_network container should be visible after navigation")
    }

    // MARK: - Row A: Health Gauge Card

    func testHealthGaugeCardIsPresent() {
        ensureNetworkDetailVisible()

        let card = ui("networkDetail_row_health").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5),
                      "network_detail_row_health (HealthGaugeCard wrapper) should be present")
    }

    func testHealthGaugeScoreTextIsVisible() {
        ensureNetworkDetailVisible()

        // healthGauge_label_score is set on the center score Text inside HealthGaugeCard
        let scoreText = app.staticTexts["healthGauge_label_score"]
        XCTAssertTrue(scoreText.waitForExistence(timeout: 5),
                      "healthGauge_label_score should be visible (score or '—')")

        // Must be a non-empty string (score, dash, or ellipsis while calculating).
        // macOS 27 reports a Text's string as its value, not its label.
        let text = scoreText.label.isEmpty ? stringValue(scoreText) : scoreText.label
        XCTAssertFalse(text.isEmpty,
                       "Health gauge score text should not be empty")
    }

    // MARK: - Row B: Left column cards

    func testISPCardIsPresent() {
        ensureNetworkDetailVisible()
        requireExists(ui("networkDetail_card_isp").firstMatch, timeout: 5,
                      message: "network_detail_card_isp should be present in the left column")
    }

    func testLatencyAnalysisCardIsPresent() {
        ensureNetworkDetailVisible()
        requireExists(ui("networkDetail_card_latency").firstMatch, timeout: 5,
                      message: "network_detail_card_latency should be present in the left column")
    }

    func testConnectivityCardIsPresent() {
        ensureNetworkDetailVisible()
        requireExists(ui("networkDetail_card_connectivity").firstMatch, timeout: 5,
                      message: "network_detail_card_connectivity should be present in the left column")
    }

    func testNetworkIntelCardIsPresent() {
        ensureNetworkDetailVisible()
        requireExists(ui("networkDetail_card_intel").firstMatch, timeout: 5,
                      message: "network_detail_card_intel should be present in the left column")
    }

    // MARK: - Row B: Right column — NetworkDevicesPanel

    func testNetworkDevicesPanelIsPresent() {
        ensureNetworkDetailVisible()
        requireExists(ui("networkDetail_section_devices").firstMatch, timeout: 5,
                      message: "network_detail_panel_devices should be present in the right column")
    }

    func testDevicesPanelShowsEmptyStateOrDeviceList() {
        ensureNetworkDetailVisible()

        // Either the device list or the empty state placeholder should be visible.
        // We accept both: the panel is functional either way.
        let panelList  = app.scrollViews["networkDevicesPanel_list_devices"]
        let panelEmpty = ui("networkDevicesPanel_label_empty").firstMatch

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
            ("networkDetail_row_health", "HealthGaugeCard row wrapper"),
            ("networkDetail_card_isp", "ISPHealthCard"),
            ("networkDetail_card_latency", "LatencyAnalysisCard"),
            ("networkDetail_card_connectivity", "ConnectivityCard"),
            ("networkDetail_card_intel", "NetworkIntelCard"),
            ("networkDetail_section_devices", "NetworkDevicesPanel"),
        ]

        for item in identifiers {
            XCTAssertTrue(
                ui(item.id).firstMatch.waitForExistence(timeout: 5),
                "\(item.description) (\(item.id)) should be present in NetworkDetailView"
            )
        }
    }
}
