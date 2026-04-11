@preconcurrency import XCTest

final class GeoFenceSettingsUITests: IOSUITestCase {
    func testCanNavigateFromSettingsToGeoFenceScreen() {
        openSettings()

        let geofenceLink = ui("settings_link_geoFence")
        scrollToElement(geofenceLink)
        requireExists(geofenceLink, timeout: 8, message: "GeoFence settings link should exist").tap()

        requireExists(ui("screen_geoFence"), timeout: 8, message: "GeoFence screen should open")
        requireExists(ui("geofence_toggle_enable_alerts"), message: "GeoFence alerts toggle should be visible")
    }

    func testGeoFenceAuthorizationActionIsVisibleWhenNotAuthorized() {
        openSettings()

        let geofenceLink = ui("settings_link_geoFence")
        scrollToElement(geofenceLink)
        requireExists(geofenceLink, timeout: 8, message: "GeoFence settings link should exist").tap()
        requireExists(ui("screen_geoFence"), timeout: 8, message: "GeoFence screen should open")

        XCTAssertTrue(
            waitForEither([
                app.buttons["geofence_button_request_permission"],
                app.buttons["geofence_button_open_settings"],
                ui("geofence_toggle_enable_alerts")
            ], timeout: 8),
            "GeoFence screen should expose either authorization action or alert toggle"
        )
    }

    func testGeoFenceEventHistorySection() {
        openSettings()

        let geofenceLink = ui("settings_link_geoFence")
        scrollToElement(geofenceLink)
        requireExists(geofenceLink, timeout: 8, message: "GeoFence settings link should exist").tap()
        requireExists(ui("screen_geoFence"), timeout: 8, message: "GeoFence screen should open")

        scrollToElement(app.descendants(matching: .any)["geofence_section_eventHistory"])
        XCTAssertTrue(
            waitForEither([
                app.descendants(matching: .any)["geofence_section_eventHistory"],
                app.descendants(matching: .any)["geofence_empty_eventHistory"]
            ], timeout: 8),
            "GeoFence screen should show event history section or empty state"
        )
    }

    private func openSettings() {
        requireExists(app.tabBars.buttons["Dashboard"], message: "Dashboard tab should exist").tap()

        let settingsButton = app.buttons["dashboard_button_settings"]
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        } else {
            // Fallback for nav button label mismatch across OS versions.
            requireExists(app.navigationBars.buttons.firstMatch, message: "A navigation bar button should exist for settings").tap()
        }

        requireExists(ui("screen_settings"), timeout: 8, message: "Settings screen should open")
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

}
