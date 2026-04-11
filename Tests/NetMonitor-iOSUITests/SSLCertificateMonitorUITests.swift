import XCTest

final class SSLCertificateMonitorUITests: IOSUITestCase {
    func testSSLMonitorQueryValidationAndOutcome() {
        openSSLMonitor()

        let queryButton = requireExists(
            app.buttons["sslMonitor_button_query"],
            message: "SSL monitor query button should exist"
        )
        XCTAssertFalse(queryButton.isEnabled, "Query button should be disabled with empty domain")

        clearAndTypeText("example.com", into: app.textFields["sslMonitor_textfield_domain"])
        XCTAssertTrue(queryButton.isEnabled, "Query button should be enabled with a domain")

        queryButton.tap()

        XCTAssertTrue(
            waitForEither([
                ui("sslMonitor_label_error"),
                ui("sslMonitor_card_ssl"),
                ui("sslMonitor_card_whois"),
                app.buttons["sslMonitor_button_add"]
            ], timeout: 20),
            "SSL query should produce visible success/error outcome"
        )

        requireExists(ui("screen_sslCertificateMonitor"), message: "SSL monitor screen should remain visible")
    }

    func testSSLMonitorWatchListSegmentAndControls() {
        openSSLMonitor()

        requireExists(
            ui("sslMonitor_picker_view"),
            message: "SSL monitor segmented view picker should be visible"
        )

        let watchListSegment = app.segmentedControls.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Watch List'")
        ).firstMatch
        requireExists(watchListSegment, message: "Watch List segment should be visible").tap()

        requireExists(
            ui("sslMonitor_section_watchlist"),
            message: "Watch list section should be visible"
        )
        requireExists(
            app.buttons["sslMonitor_button_refreshAll"],
            message: "Refresh-all control should be visible in watch list mode"
        )

        // In deterministic UI mode this is typically empty, but row presence is also acceptable.
        XCTAssertTrue(
            waitForEither([
                ui("sslMonitor_label_watchlistEmpty"),
                app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'sslMonitor_row_'")).firstMatch
            ], timeout: 6),
            "Watch list should render either empty state or rows"
        )
    }

    func testSSLQueryResultShowsCertificateDetails() {
        openSSLMonitor()
        clearAndTypeText("google.com", into: app.textFields["sslMonitor_textfield_domain"])
        app.buttons["sslMonitor_button_query"].tap()

        // Wait for result — either SSL card with details or error
        XCTAssertTrue(
            waitForEither([
                ui("sslMonitor_card_ssl"),
                ui("sslMonitor_label_error"),
                ui("sslMonitor_card_whois"),
                app.buttons["sslMonitor_button_add"]
            ], timeout: 20),
            "SSL query for google.com should produce a visible success or error outcome"
        )

        // If ssl_card appeared, verify it contains issuer/expiry/valid info
        let sslCard = ui("sslMonitor_card_ssl")
        if sslCard.exists {
            let hasDetails = app.staticTexts.matching(NSPredicate(format:
                "label CONTAINS[c] 'issuer' OR label CONTAINS[c] 'expir' OR label CONTAINS[c] 'valid' OR label CONTAINS[c] 'google'"
            )).firstMatch.exists
            XCTAssertTrue(hasDetails, "SSL card should contain certificate details such as issuer or expiry")
        }
        // Accept error as valid outcome (network may be unavailable on simulator)
    }

    func testSSLMonitorSegmentSwitchChangesContent() {
        openSSLMonitor()

        // Start on Query tab — verify query input visible
        let queryInput = app.textFields["sslMonitor_textfield_domain"]
        requireExists(queryInput, message: "Query input should be visible on Query tab")

        // Switch to Watch List tab
        let watchListSegment = app.segmentedControls.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Watch List'")
        ).firstMatch
        requireExists(watchListSegment, message: "Watch List segment should exist").tap()

        // Verify watch list content is now shown
        let watchListSection = ui("sslMonitor_section_watchlist")
        requireExists(watchListSection, message: "Watch list should be visible after segment switch")

        // Verify query input is no longer hittable (content actually changed)
        XCTAssertFalse(queryInput.isHittable, "Query input should not be hittable on Watch List tab")
    }

    private func openSSLMonitor() {
        openToolsRoot()

        let card = ui("tools_card_ssl_monitor")
        scrollToElement(card)
        requireExists(card, timeout: 8, message: "SSL Monitor tool card should exist").tap()

        requireExists(
            ui("screen_sslCertificateMonitor"),
            timeout: 8,
            message: "SSL monitor screen should open from tools grid"
        )
    }

    private func openToolsRoot() {
        requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist").tap()
        requireExists(ui("screen_tools"), timeout: 8, message: "Tools root should be visible")
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

}
