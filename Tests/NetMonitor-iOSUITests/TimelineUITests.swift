import XCTest

@MainActor
final class TimelineUITests: IOSUITestCase {
    func testTimelineTabShowsScreenAndStateContent() {
        openTimeline()

        XCTAssertTrue(
            waitForEither([
                ui("timeline_empty_state"),
                ui("timeline_list")
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
            ui("screen_timeline_filter"),
            timeout: 5,
            message: "Timeline filter sheet should open"
        )

        let showAllButton = requireExists(
            app.buttons["timeline_filter_show_all"],
            message: "Show All button should be visible in filter sheet"
        )
        showAllButton.tap()

        XCTAssertTrue(
            waitForDisappearance(ui("screen_timeline_filter"), timeout: 5),
            "Filter sheet should dismiss after selecting Show All"
        )

        // Re-open and verify Done dismissal path as well.
        filterButton.tap()
        requireExists(ui("screen_timeline_filter"), message: "Filter sheet should open on second attempt")
        requireExists(app.buttons["timeline_filter_button_done"], message: "Done button should be present").tap()

        XCTAssertTrue(
            waitForDisappearance(ui("screen_timeline_filter"), timeout: 5),
            "Filter sheet should dismiss after tapping Done"
        )
    }

    func testTimelineScreenExistsAndScrollable() {
        openTimeline()

        let timelineScreen = ui("screen_networkTimeline")
        XCTAssertTrue(timelineScreen.exists, "Timeline screen should be visible")

        app.swipeUp()
        XCTAssertTrue(timelineScreen.exists, "Timeline screen should remain visible after swipe")
    }

    func testTimelineFilterIfAvailable() {
        openTimeline()

        let filterButton = app.buttons["timeline_button_filters"]
        guard filterButton.waitForExistence(timeout: 5) else { return }

        filterButton.tap()

        guard ui("screen_timeline_filter").waitForExistence(timeout: 5) else { return }

        let showAllButton = app.buttons["timeline_filter_show_all"]
        let doneButton = app.buttons["timeline_filter_button_done"]
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
            waitForDisappearance(ui("screen_timeline_filter"), timeout: 5),
            "Filter sheet should dismiss after selection"
        )
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

    private func waitForEither(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }
}
