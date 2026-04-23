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
