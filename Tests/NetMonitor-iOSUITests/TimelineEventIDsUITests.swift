import XCTest

/// #491 S4 user flow: a scan's events are named by the device's saved custom name.
///
/// Launches with the fake discovery service (`UITEST_FAKE_DEVICES=1`), the event listener
/// (`--uitesting-events`) and a saved row for the first fixture device named "UITest Office
/// Printer" on the UI-test network (`--seed-timeline-device`). The scan runs from the Map tab
/// through the same fake service the listener watches, so nothing touches the real network.
@MainActor
final class TimelineEventIDsUITests: IOSUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["UITEST_FAKE_DEVICES": "1"]
    }

    private func relaunchRecordingEvents() {
        app.terminate()
        // `--uitesting-reset` also empties the event history, so nothing from an earlier run shows.
        app.launchArguments = ["--uitesting", "--uitesting-reset", "--uitesting-events", "--seed-timeline-device"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should relaunch to foreground")
    }

    private func openTimeline() {
        requireExists(app.tabBars.buttons["Timeline"], message: "Timeline tab should exist").tap()
        requireExists(
            app.descendants(matching: .any).matching(identifier: "screen_networkTimeline").firstMatch,
            timeout: 8, message: "Timeline should open"
        )
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAScanLogsTheSavedCustomNameInTheTimeline() {
        relaunchRecordingEvents()
        let joined = app.staticTexts["Device Joined: UITest Office Printer"]

        openTimeline()
        XCTAssertFalse(joined.exists, "No join is logged before the scan")

        requireExists(app.tabBars.buttons["Map"], message: "Map tab should exist").tap()
        let scan = app.descendants(matching: .any).matching(identifier: "networkMap_button_scan").firstMatch
        requireExists(scan, timeout: 8, message: "Map scan button should exist").tap()
        // A completed scan can bring up the App Store review prompt, which isn't a system alert.
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) {
            notNow.tap()
        }

        openTimeline()
        requireExists(joined, timeout: 10, message: "The scan's join should use the saved custom name")
        let scanComplete = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Scan Complete'")).firstMatch
        requireExists(scanComplete, timeout: 5, message: "The scan should log Scan Complete")
        XCTAssertFalse(app.staticTexts["Device Joined: uitest-device-0"].exists, "The fixture hostname must not replace the custom name")
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot(named: "timeline-custom-name")

        // The scan happened today, so the Today range (#491 S3) keeps both events.
        let todaySegment = app.segmentedControls.buttons["Today"]
        requireExists(todaySegment, timeout: 5, message: "The range picker should offer Today").tap()
        requireExists(joined, timeout: 5, message: "Today keeps the scan's join")
        XCTAssertTrue(scanComplete.exists, "Today keeps Scan Complete")
        attachScreenshot(named: "timeline-scan-today")
    }
}
