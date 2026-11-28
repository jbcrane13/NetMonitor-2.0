import XCTest

@MainActor
final class SSLCertificateMonitorUITests: MacOSUITestCase {

    func testSSLMonitorOpensFromToolsGrid() {
        openSSLMonitor()
    }

    func testSSLMonitorHasInputAndQueryButton() {
        openSSLMonitor()

        requireExists(
            app.descendants(matching: .any)["sslMonitor_textfield_domain"],
            message: "Domain input field should be visible"
        )

        let queryButton = app.buttons["sslMonitor_button_query"]
        requireExists(queryButton, message: "Query button should be visible")
        XCTAssertFalse(queryButton.isEnabled, "Query button should be disabled with empty domain")
    }

    func testSSLMonitorPickerIsVisible() {
        openSSLMonitor()

        requireExists(
            app.descendants(matching: .any)["sslMonitor_picker_view"],
            message: "Mode segmented control should be visible"
        )
    }

    func testSSLMonitorQueryButtonEnablesWithDomain() {
        openSSLMonitor()

        let domainField = app.descendants(matching: .any)["sslMonitor_textfield_domain"].firstMatch
        requireExists(domainField, message: "Domain field should exist")
        domainField.click()
        domainField.typeText("example.com")

        let queryButton = app.buttons["sslMonitor_button_query"]
        XCTAssertTrue(queryButton.isEnabled, "Query button should be enabled after entering a domain")
    }

    func testSSLMonitorWatchListTabShowsSection() {
        openSSLMonitor()

        // The segmented picker is a RadioGroup on macOS 27.
        let watchListSegment = app.radioGroups["sslMonitor_picker_view"].radioButtons.matching(
            NSPredicate(format: "label BEGINSWITH 'Watch List'")
        ).firstMatch
        requireExists(watchListSegment, message: "Watch List segment should exist").click()

        XCTAssertTrue(
            waitForEither([
                ui("sslMonitor_label_watchlistEmpty").firstMatch,
                app.descendants(matching: .any).matching(
                    NSPredicate(format: "identifier BEGINSWITH 'sslMonitor_row_'")
                ).firstMatch
            ], timeout: 5),
            "Watch list should show empty state or rows"
        )
    }

    // MARK: - Helpers

    private func openSSLMonitor() {
        navigateToSidebar("tools")
        let card = ui("tools_card_ssl_monitor").firstMatch
        requireExists(card, timeout: 8, message: "SSL Monitor tool card should exist in tools grid").click()

        requireExists(
            app.descendants(matching: .any)["sslMonitor_textfield_domain"],
            timeout: 8,
            message: "SSL Monitor sheet should open"
        )
    }
}
