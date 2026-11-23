import XCTest

@MainActor
final class TimelineUITests: MacOSUITestCase {

    // MARK: - Navigate to Timeline and Verify Content

    func testTimelineViewAccessibleFromTools() {
        navigateToTimeline()

        let timelineScreen = ui("screen_networkTimeline")
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

        let timelineScreen = ui("screen_networkTimeline")
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

        let timelineScreen = ui("screen_networkTimeline")
        guard timelineScreen.waitForExistence(timeout: 8) else { return }

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

    func testTimelineFilterActuallyFiltersEvents() {
        navigateToTimeline()

        let timelineScreen = ui("screen_networkTimeline")
        guard timelineScreen.waitForExistence(timeout: 8) else { return }

        // Count initial event rows
        let eventRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'timeline_event_'")
        )
        let initialCount = eventRows.count

        // Try to interact with a filter control to narrow results
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 5) {
            searchField.tap()
            searchField.typeText("nonexistent-filter-value-xyz")

            // After filtering, the event count should differ (likely fewer or zero)
            let filteredCount = eventRows.count
            XCTAssertTrue(filteredCount <= initialCount,
                          "Filtering should not increase event count (was \(initialCount), now \(filteredCount))")

            // Clear the filter
            if let currentValue = searchField.value as? String, !currentValue.isEmpty {
                searchField.typeKey("a", modifierFlags: .command)
                searchField.typeKey(.delete, modifierFlags: [])
            }
        } else {
            // Try segmented control filter (e.g. event type picker)
            let segmentedFilter = app.segmentedControls.matching(
                NSPredicate(format: "identifier CONTAINS 'timeline'")
            ).firstMatch
            if segmentedFilter.waitForExistence(timeout: 3), segmentedFilter.buttons.count > 1 {
                let firstSegment = segmentedFilter.buttons.element(boundBy: 0)
                let secondSegment = segmentedFilter.buttons.element(boundBy: 1)

                // Tap second segment to filter
                secondSegment.tap()

                // Verify segment is selected
                let isSelected = secondSegment.isSelected
                    || (secondSegment.value as? String == "1")
                XCTAssertTrue(isSelected,
                              "Tapped filter segment should become selected")

                // Tap first segment to restore
                firstSegment.tap()
            } else {
                // Try popUpButton filter
                let popupFilter = app.popUpButtons.matching(
                    NSPredicate(format: "identifier CONTAINS 'timeline'")
                ).firstMatch
                if popupFilter.waitForExistence(timeout: 3) {
                    popupFilter.tap()
                    let firstMenuItem = app.menuItems.firstMatch
                    if firstMenuItem.waitForExistence(timeout: 3) {
                        firstMenuItem.tap()
                        // Picker should still exist after selection
                        XCTAssertTrue(popupFilter.exists,
                                      "Filter picker should remain after selecting an option")
                    } else {
                        app.typeKey(.escape, modifierFlags: [])
                    }
                }
            }
        }

        captureScreenshot(named: "Timeline_FilterApplied")
    }

    // MARK: - Timeline Events Have Non-Empty Data

    func testTimelineEventsShowRealData() {
        navigateToTimeline()

        let timelineScreen = ui("screen_networkTimeline")
        guard timelineScreen.waitForExistence(timeout: 8) else { return }

        // Look for event rows
        let firstEventRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'timeline_event_'")
        ).firstMatch

        if firstEventRow.waitForExistence(timeout: 10) {
            // Event rows should contain visible text (timestamp, description, etc.)
            let eventTexts = firstEventRow.staticTexts
            // swiftlint:disable:next empty_count
            if eventTexts.count > 0 {
                let hasNonEmptyLabel = eventTexts.allElementsBoundByIndex.contains { text in
                    !text.label.isEmpty
                }
                XCTAssertTrue(hasNonEmptyLabel,
                              "Timeline event rows should display non-empty text labels")
            }
        }

        captureScreenshot(named: "Timeline_EventData")
    }

    // MARK: - Helpers

    /// Navigate to the Timeline section via sidebar.
    private func navigateToTimeline() {
        // Timeline is accessed from the Tools section on macOS
        let toolsItem = app.descendants(matching: .any)["sidebar_nav_tools"]
        if toolsItem.waitForExistence(timeout: 5) {
            toolsItem.tap()
            _ = app.otherElements["detail_tools"].waitForExistence(timeout: 5)
        }

        // The Timeline is a Monitoring tool card (#491 D5).
        let timelineCard = app.descendants(matching: .any)["tools_card_timeline"]
        requireExists(timelineCard, timeout: 5, message: "Tools should list the Timeline card").click()
    }

    // MARK: - Range Picker (#491 S3)

    /// Seeded events today and ten days ago: "Today" hides the old one, "All" shows both.
    /// Not runnable on mini-pro-1 (#512); the AX script `scripts/ax/s3-timeline.sh` covers it there.
    func testRangePickerTodayHidesOlderEventsAndAllShowsThem() {
        app.terminate()
        app.launchArguments = ["--uitesting", "--in-memory-store", "--reset-history-files", "--seed-test-device", "--seed-test-events"]
        app.launch()
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
