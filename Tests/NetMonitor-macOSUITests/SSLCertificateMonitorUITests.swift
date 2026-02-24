import XCTest

@MainActor
final class SSLCertificateMonitorUITests: MacOSUITestCase {

    func testSSLMonitorOpensFromToolsGrid() {
        openSSLMonitor()
    }

    func testSSLMonitorHasInputAndQueryButton() {
        openSSLMonitor()

        requireExists(
            app.descendants(matching: .any)["ssl_monitor_input_domain"],
            message: "Domain input field should be visible"
        )

        let queryButton = app.buttons["ssl_monitor_button_query"]
        requireExists(queryButton, message: "Query button should be visible")
        XCTAssertFalse(queryButton.isEnabled, "Query button should be disabled with empty domain")
    }

    func testSSLMonitorPickerIsVisible() {
        openSSLMonitor()

        requireExists(
            app.descendants(matching: .any)["ssl_monitor_picker_view"],
            message: "Mode segmented control should be visible"
        )
    }

    func testSSLMonitorQueryButtonEnablesWithDomain() {
        openSSLMonitor()

        let domainField = app.descendants(matching: .any)["ssl_monitor_input_domain"].firstMatch
        requireExists(domainField, message: "Domain field should exist")
        domainField.click()
        domainField.typeText("example.com")

        let queryButton = app.buttons["ssl_monitor_button_query"]
        XCTAssertTrue(queryButton.isEnabled, "Query button should be enabled after entering a domain")
    }

    func testSSLMonitorWatchListTabShowsSection() {
        openSSLMonitor()

        let watchListSegment = app.segmentedControls.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Watch List'")
        ).firstMatch

        if watchListSegment.waitForExistence(timeout: 5) {
            watchListSegment.click()

            XCTAssertTrue(
                waitForEither([
                    app.descendants(matching: .any)["ssl_monitor_watchlist_empty"],
                    app.descendants(matching: .any).matching(
                        NSPredicate(format: "identifier BEGINSWITH 'ssl_monitor_watchlist_row_'")
                    ).firstMatch
                ], timeout: 5),
                "Watch list should show empty state or rows"
            )
        }
    }

    // MARK: - Helpers

    private func openSSLMonitor() {
        let card = app.descendants(matching: .any)["tools_card_ssl_monitor"]
        scrollToElement(card)
        requireExists(card, timeout: 8, message: "SSL Monitor tool card should exist in tools grid").tap()

        requireExists(
            app.descendants(matching: .any)["ssl_monitor_input_domain"],
            timeout: 8,
            message: "SSL Monitor sheet should open"
        )
    }

    private func scrollToElement(_ element: XCUIElement, maxScrolls: Int = 5) {
        guard !element.exists else { return }
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<maxScrolls {
            if element.exists { return }
            scroll.swipeUp()
        }
    }

    private func waitForEither(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
