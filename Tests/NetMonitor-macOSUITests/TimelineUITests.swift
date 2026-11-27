import XCTest

@MainActor
final class TimelineUITests: MacOSUITestCase {

    // MARK: - Navigate to Timeline and Verify Content

    func testTimelineViewAccessibleFromTools() {
        navigateToTimeline()

        let timelineScreen = ui("screen_networkTimeline").firstMatch
        XCTAssertTrue(timelineScreen.waitForExistence(timeout: 8),
                      "Timeline screen should be visible after navigating to it")

        // Verify timeline has event content or empty state — not just a blank container
        let hasContent = waitForEither([
            app.descendants(matching: .any)["timeline_list_events"],
            app.staticTexts.matching(
                NSPredicate(format: "identifier BEGINSWITH 'timeline_event_'")
            ).firstMatch,
            ui("timeline_label_empty"),
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'No events'")
            ).firstMatch
        ], timeout: 5)

        XCTAssertTrue(hasContent,
                      "Timeline should display event list or empty state, not just a container")

        captureScreenshot(named: "Timeline_Accessible")
    }

    func testTimelineScreenIdentifierExists() {
        navigateToTimeline()

        let timelineScreen = ui("screen_networkTimeline").firstMatch
        XCTAssertTrue(timelineScreen.waitForExistence(timeout: 8),
                      "Timeline screen identifier should be accessible")

        // Verify the timeline screen has structural elements — filter bar, event list
        let hasStructure = waitForEither([
            app.textFields.matching(
                NSPredicate(format: "identifier CONTAINS 'timeline' AND identifier CONTAINS 'filter'")
            ).firstMatch,
            app.searchFields.matching(
                NSPredicate(format: "identifier CONTAINS 'timeline'")
            ).firstMatch,
            app.segmentedControls.matching(
                NSPredicate(format: "identifier CONTAINS 'timeline'")
            ).firstMatch,
            app.popUpButtons.matching(
                NSPredicate(format: "identifier CONTAINS 'timeline'")
            ).firstMatch,
            ui("timeline_picker_range"),
            app.tables.firstMatch
        ], timeout: 5)

        XCTAssertTrue(hasStructure,
                      "Timeline screen should contain filter controls or event table, not just a label")

        captureScreenshot(named: "Timeline_Structure")
    }

    // MARK: - Filter Actually Filters Events

    func testTimelineFilterControlsArePresent() {
        navigateToTimeline()

        let timelineScreen = ui("screen_networkTimeline").firstMatch
        requireExists(timelineScreen, timeout: 8, message: "Timeline screen should be visible")

        // Look for any filter/search/picker controls in the timeline
        let filterControls = [
            app.searchFields.firstMatch,
            app.textFields.matching(
                NSPredicate(format: "identifier CONTAINS 'filter'")
            ).firstMatch,
            app.segmentedControls.matching(
                NSPredicate(format: "identifier CONTAINS 'timeline' OR identifier CONTAINS 'filter'")
            ).firstMatch,
            app.popUpButtons.matching(
                NSPredicate(format: "identifier CONTAINS 'timeline'")
            ).firstMatch,
            ui("timeline_picker_eventType"),
            ui("timeline_picker_range")
        ]

        let hasFilterControl = waitForEither(filterControls, timeout: 5)
        XCTAssertTrue(hasFilterControl,
                      "Timeline should have at least one filter/search/picker control")

        captureScreenshot(named: "Timeline_FilterControls")
    }

    /// Both seeded events are connectivity changes: another event type hides them
    /// and "All Events" brings them back.
    func testTimelineFilterActuallyFiltersEvents() {
        relaunchWithSeededEvents()
        navigateToTimeline()

        let today = app.staticTexts["UITest Event Today"]
        requireExists(today, timeout: 8, message: "All Events (the default) shows the seeded event")

        let typePicker = requireExists(app.popUpButtons["timeline_picker_eventType"],
                                       message: "Timeline should offer an event type filter")
        select("Device Joined", in: typePicker)
        XCTAssertTrue(waitForDisappearance(today, timeout: 5),
                      "Filtering by Device Joined should hide the connectivity events")
        requireExists(ui("timeline_label_empty").firstMatch,
                      message: "A filter that matches nothing should show the empty state")
        captureScreenshot(named: "Timeline_FilterApplied")

        select("All Events", in: typePicker)
        requireExists(today, timeout: 5, message: "All Events should show the seeded event again")
    }

    // MARK: - Timeline Events Have Non-Empty Data

    func testTimelineEventsShowRealData() {
        relaunchWithSeededEvents()
        navigateToTimeline()
        requireExists(ui("screen_networkTimeline").firstMatch, timeout: 8,
                      message: "Timeline screen should be visible")

        // A row's id is stamped onto its icon and texts on macOS 27, and a Text
        // reports its string as its value.
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'timeline_event_'")
        )
        requireExists(rows.firstMatch, timeout: 10, message: "Seeded events should be listed as rows")
        let texts = (rows.allElementsBoundByIndex + rows.staticTexts.allElementsBoundByIndex)
            .map { $0.label.isEmpty ? stringValue($0) : $0.label }
        XCTAssertTrue(texts.contains("UITest Event Today"),
                      "Timeline event rows should display the event's title, got \(texts)")

        captureScreenshot(named: "Timeline_EventData")
    }

    // MARK: - Helpers

    /// Navigate to the Timeline section via sidebar.
    private func navigateToTimeline() {
        // The Timeline is a Monitoring tool card (#491 D5).
        navigateToSidebar("tools")
        let timelineCard = ui("tools_card_timeline").firstMatch
        requireExists(timelineCard, timeout: 5, message: "Tools should list the Timeline card").click()
    }

    /// Relaunch with one event today and one ten days ago, on an empty history.
    private func relaunchWithSeededEvents() {
        app.terminate()
        app.launchArguments = ["--uitesting", "--in-memory-store", "--reset-history-files", "--seed-test-device", "--seed-test-events"]
        app.launch()
    }

    /// Choose an option from a pop-up picker. The menu is read from the picker
    /// itself: `app.menuItems` starts with the Apple menu in the menu bar.
    private func select(_ option: String, in picker: XCUIElement) {
        picker.click()
        requireExists(picker.menuItems[option], timeout: 3,
                      message: "\(picker) should offer \(option)").click()
    }

    // MARK: - Range Picker (#491 S3)

    /// Seeded events today and ten days ago: "Today" hides the old one, "All" shows both.
    /// Not runnable on mini-pro-1 (#512); the AX script `scripts/ax/s3-timeline.sh` covers it there.
    func testRangePickerTodayHidesOlderEventsAndAllShowsThem() {
        relaunchWithSeededEvents()
        navigateToTimeline()

        let today = app.staticTexts["UITest Event Today"]
        let tenDaysAgo = app.staticTexts["UITest Event 10 Days Ago"]
        requireExists(today, timeout: 8, message: "All (the default) shows today's event")
        XCTAssertTrue(tenDaysAgo.exists, "All (the default) shows the event from ten days ago")

        let picker = app.radioGroups["timeline_picker_range"]
        let segments = picker.exists ? picker.radioButtons : app.radioButtons
        requireExists(segments["Today"], message: "The range picker should offer Today").click()
        requireExists(today, timeout: 5, message: "Today shows today's event")
        XCTAssertTrue(waitForDisappearance(tenDaysAgo, timeout: 5), "Today hides the event from ten days ago")
        captureScreenshot(named: "Timeline_RangeToday")

        segments["All"].click()
        requireExists(tenDaysAgo, timeout: 5, message: "All shows the event from ten days ago again")
        XCTAssertTrue(today.exists, "All still shows today's event")
        captureScreenshot(named: "Timeline_RangeAll")
    }
}
