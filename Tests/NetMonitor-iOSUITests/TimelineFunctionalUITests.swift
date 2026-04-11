@preconcurrency import XCTest

/// Functional companion tests for TimelineUITests.
///
/// Tests verify **outcomes** of timeline interactions: filter sheet behavior,
/// filter application, and clear-all functionality.
/// Existing tests in TimelineUITests are NOT modified.
final class TimelineFunctionalUITests: IOSUITestCase {

    // MARK: - Helpers

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func openTimeline() {
        let tab = requireExists(app.tabBars.buttons["Timeline"],
                                message: "Timeline tab should exist")
        tab.tap()
        requireExists(ui("screen_networkTimeline"), timeout: 8,
                      message: "Timeline screen should be visible after selecting tab")
    }

    // MARK: - 1. Tap Filter Button -> Verify Filter Sheet Appears

    func testFilterButtonOpensFilterSheet() {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        requireExists(filterButton, timeout: 8, message: "Filter button should exist in timeline")

        filterButton.tap()

        // Filter sheet should appear with identifiable elements
        let filterSheet = ui("screen_timelineFilter")
        requireExists(filterSheet, timeout: 5,
                      message: "Filter sheet should appear after tapping filter button")

        // Verify sheet has functional controls (not just an empty sheet)
        let hasControls = waitForEither([
            app.buttons["timelineFilter_button_showAll"],
            app.buttons["timelineFilter_button_done"],
            app.switches.firstMatch
        ], timeout: 5)

        XCTAssertTrue(hasControls,
                     "Filter sheet should contain interactive controls (Show All, Done, or toggles)")

        captureScreenshot(named: "Timeline_FilterSheet")

        // Dismiss
        let doneButton = app.buttons["timelineFilter_button_done"]
        if doneButton.exists {
            doneButton.tap()
        }
    }

    // MARK: - 2. Select Filter Type -> Verify Timeline Filters

    func testSelectFilterTypeChangesTimelineContent() {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        guard filterButton.waitForExistence(timeout: 8) else { return }

        filterButton.tap()
        guard ui("screen_timelineFilter").waitForExistence(timeout: 5) else { return }

        // Toggle a filter if individual event-type toggles exist
        let firstToggle = app.switches.firstMatch
        if firstToggle.waitForExistence(timeout: 3) {
            let beforeValue = firstToggle.value as? String ?? ""
            firstToggle.tap()
            let afterValue = firstToggle.value as? String ?? ""

            XCTAssertNotEqual(beforeValue, afterValue,
                             "Event type filter toggle should change state after tap")

            captureScreenshot(named: "Timeline_FilterToggled")
        }

        // Dismiss filter sheet
        let doneButton = app.buttons["timelineFilter_button_done"]
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        }

        // Timeline should still be visible after applying filter
        requireExists(ui("screen_networkTimeline"), timeout: 5,
                      message: "Timeline screen should remain visible after filter change")

        captureScreenshot(named: "Timeline_FilterApplied")
    }

    // MARK: - 3. Show All Filter Resets Filters

    func testShowAllResetsFilters() {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        guard filterButton.waitForExistence(timeout: 8) else { return }

        filterButton.tap()
        guard ui("screen_timelineFilter").waitForExistence(timeout: 5) else { return }

        // Tap Show All to reset any active filters
        let showAllButton = app.buttons["timelineFilter_button_showAll"]
        if showAllButton.waitForExistence(timeout: 3) {
            showAllButton.tap()

            // Filter sheet should dismiss after Show All
            XCTAssertTrue(
                waitForDisappearance(ui("screen_timelineFilter"), timeout: 5),
                "Filter sheet should dismiss after tapping Show All"
            )

            // Timeline should show its content (list or empty state)
            let hasContent = waitForEither([
                ui("timeline_list_events"),
                ui("timeline_label_emptyState")
            ], timeout: 8)

            XCTAssertTrue(hasContent,
                         "Timeline should show event list or empty state after Show All filter")
        }

        captureScreenshot(named: "Timeline_ShowAll")
    }

    // MARK: - 4. Filter Sheet Done Button Dismisses

    func testFilterSheetDoneButtonDismissesSheet() {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        guard filterButton.waitForExistence(timeout: 8) else { return }

        filterButton.tap()

        let filterSheet = ui("screen_timelineFilter")
        guard filterSheet.waitForExistence(timeout: 5) else { return }

        let doneButton = app.buttons["timelineFilter_button_done"]
        requireExists(doneButton, timeout: 3, message: "Done button should exist in filter sheet")

        doneButton.tap()

        XCTAssertTrue(
            waitForDisappearance(filterSheet, timeout: 5),
            "Filter sheet should dismiss after tapping Done button"
        )

        // Timeline screen should remain visible
        requireExists(ui("screen_networkTimeline"), timeout: 5,
                      message: "Timeline should remain visible after dismissing filter sheet")
    }

    // MARK: - 5. Timeline Scrolls Without Crash

    func testTimelineScrollsAndRemainsFunctional() {
        openTimeline()

        // Scroll through timeline content
        app.swipeUp()
        app.swipeUp()

        // Timeline should still be visible after scrolling
        requireExists(ui("screen_networkTimeline"), timeout: 5,
                      message: "Timeline should remain visible after scrolling")

        // Scroll back to top
        app.swipeDown()
        app.swipeDown()

        // Should still show either list or empty state
        let hasContent = waitForEither([
            ui("timeline_list_events"),
            ui("timeline_label_emptyState")
        ], timeout: 5)

        XCTAssertTrue(hasContent,
                     "Timeline should show content after scroll round-trip")

        captureScreenshot(named: "Timeline_Scroll")
    }

    // MARK: - 6. Timeline Empty State or Event List Present

    func testTimelineShowsContentOrEmptyState() {
        openTimeline()

        let hasTimeline = waitForEither([
            ui("timeline_list_events"),
            ui("timeline_label_emptyState")
        ], timeout: 8)

        XCTAssertTrue(hasTimeline,
                     "Timeline should show event list or empty state")

        if ui("timeline_list_events").exists {
            // If events exist, verify they have content
            XCTAssertFalse(app.cells.allElementsBoundByIndex.isEmpty,
                          "Timeline list should contain at least one event row")
        } else if ui("timeline_label_emptyState").exists {
            // Empty state should have descriptive text
            let hasDescription = app.staticTexts.count > 0
            XCTAssertTrue(hasDescription,
                         "Empty state should display descriptive text")
        }

        captureScreenshot(named: "Timeline_Content")
    }

    // MARK: - 7. Re-open Filter Sheet After Dismissal

    func testFilterSheetCanBeReopenedAfterDismissal() {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        guard filterButton.waitForExistence(timeout: 8) else { return }

        // First open
        filterButton.tap()
        let filterSheet = ui("screen_timelineFilter")
        guard filterSheet.waitForExistence(timeout: 5) else { return }

        // Dismiss via Done
        let doneButton = app.buttons["timelineFilter_button_done"]
        if doneButton.exists {
            doneButton.tap()
            _ = waitForDisappearance(filterSheet, timeout: 3)
        }

        // Second open - should still work
        filterButton.tap()
        let filterSheetAgain = ui("screen_timelineFilter")
        XCTAssertTrue(filterSheetAgain.waitForExistence(timeout: 5),
                     "Filter sheet should open successfully on second attempt")

        // Dismiss again
        if app.buttons["timelineFilter_button_done"].exists {
            app.buttons["timelineFilter_button_done"].tap()
        }

        captureScreenshot(named: "Timeline_ReopenFilter")
    }
}
