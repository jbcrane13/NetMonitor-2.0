import XCTest

/// Events saved by builds before #491 (a UserDefaults blob) move to the event file on first
/// launch, a corrupt element in it doesn't lose the others, and the file keeps a new event
/// across a relaunch (#491 S1).
@MainActor
final class EventHistoryMigrationUITests: IOSUITestCase {
    /// The titles `UITestBootstrap.prepareEventHistoryIfNeeded` seeds.
    private let legacyTitles = ["Legacy: Device Joined: Old Printer", "Legacy: Scan Complete"]
    private let corruptTitle = "Legacy: Corrupt element"
    private let newTitle = "Migration check"

    func testLegacyEventsMigrateAndANewEventSurvivesRelaunch() {
        // setUp's launch passed --uitesting-reset, which cleared the files and the legacy key.
        app.terminate()
        app.launchArguments = [
            "--uitesting", "--seed-legacy-events", "--reset-history-files", "--log-test-event", newTitle
        ]
        app.launch()
        expectTimelineShowsMigratedAndNewEvents(screenshot: "timeline-first-launch-migrated")

        // No reset, no seed and no new event: what's shown now comes from the saved file.
        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launch()
        expectTimelineShowsMigratedAndNewEvents(screenshot: "timeline-after-relaunch")
    }

    private func expectTimelineShowsMigratedAndNewEvents(screenshot name: String) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should launch to foreground")
        requireExists(app.tabBars.buttons["Timeline"], message: "Timeline tab should exist").tap()
        requireExists(app.descendants(matching: .any)["screen_networkTimeline"], timeout: 8, message: "Timeline should open")
        requireExists(app.staticTexts[newTitle], timeout: 8, message: "The event logged at first launch should be listed")
        for title in legacyTitles {
            requireExists(app.staticTexts[title], message: "The migrated event \"\(title)\" should be listed")
        }
        XCTAssertFalse(app.staticTexts[corruptTitle].exists, "The corrupt legacy element should be skipped")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
