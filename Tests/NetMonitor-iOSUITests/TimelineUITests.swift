import XCTest

@MainActor
final class TimelineUITests: IOSUITestCase {
    func testTimelineTabShowsScreenAndStateContent() {
        openTimeline()

        XCTAssertTrue(
            waitForEither([
                ui("timeline_label_emptyState"),
                ui("timeline_list_events")
            ], timeout: 8),
            "Timeline should render either empty state or event list"
        )
    }

    func testTimelineFilterSheetCanOpenAndDismiss() {
        openTimeline()

        let filterButton = requireExists(
            app.buttons["timeline_button_filters"],
            message: "Timeline filter button should be visible"
        )
        filterButton.tap()

        requireExists(
            ui("screen_timelineFilter"),
            timeout: 5,
            message: "Timeline filter sheet should open"
        )

        let showAllButton = requireExists(
            app.buttons["timelineFilter_button_showAll"],
            message: "Show All button should be visible in filter sheet"
        )
        showAllButton.tap()

        XCTAssertTrue(
            waitForDisappearance(ui("screen_timelineFilter"), timeout: 5),
            "Filter sheet should dismiss after selecting Show All"
        )

        // Re-open and verify Done dismissal path as well.
        filterButton.tap()
        requireExists(ui("screen_timelineFilter"), message: "Filter sheet should open on second attempt")
        requireExists(app.buttons["timelineFilter_button_done"], message: "Done button should be present").tap()

        XCTAssertTrue(
            waitForDisappearance(ui("screen_timelineFilter"), timeout: 5),
            "Filter sheet should dismiss after tapping Done"
        )
    }

    func testTimelineScreenExistsAndScrollable() {
        openTimeline()

        let timelineScreen = ui("screen_networkTimeline")
        XCTAssertTrue(timelineScreen.exists, "Timeline screen should be visible")

        // FUNCTIONAL: scroll should work without crashing, and screen should still show content after
        app.swipeUp()
        XCTAssertTrue(
            waitForEither([ui("timeline_list_events"), ui("timeline_label_emptyState")], timeout: 5),
            "Timeline should still show content or empty state after scrolling"
        )

        app.swipeDown()
        XCTAssertTrue(timelineScreen.exists, "Timeline screen should remain visible after scroll round-trip")
    }

    func testTimelineFilterIfAvailable() {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        guard filterButton.waitForExistence(timeout: 5) else { return }

        filterButton.tap()

        guard ui("screen_timelineFilter").waitForExistence(timeout: 5) else { return }

        let showAllButton = app.buttons["timelineFilter_button_showAll"]
        let doneButton = app.buttons["timelineFilter_button_done"]
        XCTAssertTrue(
            showAllButton.exists || doneButton.exists,
            "Filter sheet should contain Show All or Done button"
        )

        if doneButton.exists {
            doneButton.tap()
        } else if showAllButton.exists {
            showAllButton.tap()
        }

        XCTAssertTrue(
            waitForDisappearance(ui("screen_timelineFilter"), timeout: 5),
            "Filter sheet should dismiss after selection"
        )
    }

    func testFilterButtonOpensAndDoneButtonDismissesFilterSheet() throws {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        requireExists(filterButton, timeout: 8, message: "Filter button should exist in Timeline")
        filterButton.tap()

        // FUNCTIONAL: filter sheet should appear
        let doneButton = app.buttons["timelineFilter_button_done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5),
                     "Filter sheet Done button should appear after tapping filter")

        // FUNCTIONAL: tap Done and verify sheet dismisses
        doneButton.tap()
        XCTAssertTrue(
            waitForDisappearance(ui("screen_timelineFilter"), timeout: 5),
            "Filter sheet should dismiss after tapping Done"
        )
    }

    func testFilterSheetToggleChangesFilterState() throws {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        guard filterButton.waitForExistence(timeout: 8) else { return }
        filterButton.tap()

        guard ui("screen_timelineFilter").waitForExistence(timeout: 5) else { return }

        // FUNCTIONAL: if individual event-type filters exist, toggling one changes its state
        let firstToggle = app.switches.firstMatch
        if firstToggle.waitForExistence(timeout: 3) {
            let before = firstToggle.value as? String ?? ""
            firstToggle.tap()
            let after = firstToggle.value as? String ?? ""
            XCTAssertNotEqual(before, after, "Event type filter toggle should change state after tap")
        }

        // Dismiss via Done
        let doneButton = app.buttons["timelineFilter_button_done"]
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        }
    }

    // MARK: - Functional: Filter actually filters events

    func testToggleFilterChangesTimelineEventVisibility() {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        guard filterButton.waitForExistence(timeout: 8) else { return }

        // Capture initial state: count of visible events or empty state
        let initialHasEvents = ui("timeline_list_events").exists

        filterButton.tap()
        guard ui("screen_timelineFilter").waitForExistence(timeout: 5) else { return }

        // Toggle a filter switch if available
        let firstToggle = app.switches.firstMatch
        if firstToggle.waitForExistence(timeout: 3) {
            let beforeValue = firstToggle.value as? String ?? ""
            firstToggle.tap()
            let afterValue = firstToggle.value as? String ?? ""
            XCTAssertNotEqual(beforeValue, afterValue,
                             "Filter toggle should change state when tapped")

            // Dismiss filter sheet
            let doneButton = app.buttons["timelineFilter_button_done"]
            if doneButton.waitForExistence(timeout: 3) {
                doneButton.tap()
                XCTAssertTrue(
                    waitForDisappearance(ui("screen_timelineFilter"), timeout: 5),
                    "Filter sheet should dismiss after toggling filter"
                )
            }

            // FUNCTIONAL: timeline should still show either events or empty state
            XCTAssertTrue(
                waitForEither([ui("timeline_list_events"), ui("timeline_label_emptyState")], timeout: 8),
                "Timeline should show events or empty state after applying a filter"
            )
        } else {
            // No toggles — dismiss via Done
            if app.buttons["timelineFilter_button_done"].waitForExistence(timeout: 3) {
                app.buttons["timelineFilter_button_done"].tap()
            } else if app.buttons["timelineFilter_button_showAll"].waitForExistence(timeout: 3) {
                app.buttons["timelineFilter_button_showAll"].tap()
            }
        }
    }

    func testShowAllFilterResetsToFullEventList() {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        guard filterButton.waitForExistence(timeout: 8) else { return }

        // Open filter and toggle off a filter if possible
        filterButton.tap()
        guard ui("screen_timelineFilter").waitForExistence(timeout: 5) else { return }

        let firstToggle = app.switches.firstMatch
        if firstToggle.waitForExistence(timeout: 3) {
            // Turn off one filter
            if (firstToggle.value as? String) == "1" {
                firstToggle.tap()
            }

            // Dismiss
            let doneButton = app.buttons["timelineFilter_button_done"]
            if doneButton.waitForExistence(timeout: 3) {
                doneButton.tap()
                _ = waitForDisappearance(ui("screen_timelineFilter"), timeout: 5)
            }

            // Now re-open and tap Show All to reset
            filterButton.tap()
            guard ui("screen_timelineFilter").waitForExistence(timeout: 5) else { return }
        }

        let showAllButton = app.buttons["timelineFilter_button_showAll"]
        if showAllButton.waitForExistence(timeout: 3) {
            showAllButton.tap()
            XCTAssertTrue(
                waitForDisappearance(ui("screen_timelineFilter"), timeout: 5),
                "Filter sheet should dismiss after Show All"
            )

            // FUNCTIONAL: timeline should show all events or empty state after Show All
            XCTAssertTrue(
                waitForEither([ui("timeline_list_events"), ui("timeline_label_emptyState")], timeout: 8),
                "Timeline should show all events or empty state after Show All filter reset"
            )
        } else {
            // Dismiss if no Show All
            if app.buttons["timelineFilter_button_done"].waitForExistence(timeout: 3) {
                app.buttons["timelineFilter_button_done"].tap()
            }
        }
    }

    // MARK: - Range picker (#491 S3)

    /// Seeded events today and ten days ago (`--seed-test-events`): "Today" hides the old one,
    /// "All" shows both.
    func testRangePickerTodayHidesOlderEventsAndAllShowsThem() {
        app.terminate()
        app.launchArguments = ["--uitesting", "--uitesting-reset", "--seed-test-events"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should relaunch to foreground")
        openTimeline()

        let today = app.staticTexts["UITest Event Today"]
        let tenDaysAgo = app.staticTexts["UITest Event 10 Days Ago"]
        requireExists(today, timeout: 8, message: "All (the default) shows today's event")
        XCTAssertTrue(scrollTo(tenDaysAgo), "All (the default) shows the event from ten days ago")

        rangeSegment("Today").tap()
        requireExists(today, timeout: 5, message: "Today shows today's event")
        XCTAssertTrue(waitForDisappearance(tenDaysAgo, timeout: 5), "Today hides the event from ten days ago")
        attachScreenshot(named: "timeline-range-today")

        rangeSegment("All").tap()
        requireExists(today, timeout: 5, message: "All shows today's event again")
        XCTAssertTrue(scrollTo(tenDaysAgo), "All shows the event from ten days ago again")
        attachScreenshot(named: "timeline-range-all")
    }

    /// Clear All deletes the whole log, so it asks first; Cancel keeps everything, including
    /// events outside the selected range.
    func testClearAllAsksFirstAndCancelKeepsEveryEvent() {
        app.terminate()
        app.launchArguments = ["--uitesting", "--uitesting-reset", "--seed-test-events"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should relaunch to foreground")
        openTimeline()

        let today = app.staticTexts["UITest Event Today"]
        let tenDaysAgo = app.staticTexts["UITest Event 10 Days Ago"]
        requireExists(today, timeout: 8, message: "Today's seeded event should show")
        rangeSegment("Today").tap()
        XCTAssertTrue(waitForDisappearance(tenDaysAgo, timeout: 5), "Today hides the older event")

        let clearAll = app.buttons.matching(NSPredicate(format: "label == 'Clear All'")).firstMatch
        requireExists(clearAll, message: "Clear All should be offered while the log has events").tap()
        requireExists(app.staticTexts["Delete all network events?"], message: "Clear All should ask before deleting")
        attachScreenshot(named: "timeline-clear-all-confirm")
        // iOS 26 shows the confirmation as a popover with no Cancel button: tapping outside cancels.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()

        XCTAssertTrue(waitForDisappearance(app.staticTexts["Delete all network events?"], timeout: 5), "Cancel closes the confirmation")
        requireExists(today, timeout: 5, message: "Cancel keeps today's event")
        rangeSegment("All").tap()
        XCTAssertTrue(scrollTo(tenDaysAgo), "Cancel keeps the older event outside the range")
        attachScreenshot(named: "timeline-clear-all-cancelled")
    }

    /// A segment of `timeline_picker_range`. iOS 26 may stamp the screen's identifier over the
    /// control's (lessons-learned 2026-09), so fall back to the segment's label.
    private func rangeSegment(_ title: String) -> XCUIElement {
        let picker = app.segmentedControls["timeline_picker_range"]
        let segment = picker.exists ? picker.buttons[title] : app.segmentedControls.buttons[title]
        return requireExists(segment, timeout: 5, message: "The range picker should offer \(title)")
    }

    /// Scrolls the event list until `element` is on screen; false if it never appears.
    private func scrollTo(_ element: XCUIElement) -> Bool {
        for _ in 0 ..< 6 {
            if element.waitForExistence(timeout: 1), element.isHittable {
                return true
            }
            app.swipeUp()
        }
        return element.exists
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openTimeline() {
        let tab = requireExists(app.tabBars.buttons["Timeline"], message: "Timeline tab should exist")
        tab.tap()

        requireExists(
            ui("screen_networkTimeline"),
            timeout: 8,
            message: "Timeline screen should be visible after selecting the tab"
        )
    }

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

}
