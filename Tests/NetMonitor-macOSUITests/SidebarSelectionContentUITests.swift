import XCTest

/// Verifies that clicking sidebar items actually swaps the detail pane's
/// contents — not merely that a sidebar row exists.
///
/// Closes the last open checkbox in PRD-issue-174:
/// "Sidebar navigation: verify content changes on selection".
///
/// The existing `SidebarNavigationUITests` and `SidebarFunctionalUITests` either
/// check only that a row exists or look for `detail_*` identifiers that are not
/// produced by the current app. These tests use the real identifiers rendered
/// by `ContentView.detailView` (`contentView_nav_*`) plus per-section content
/// identifiers so we can assert that:
///
///   1. The correct content container renders after selection.
///   2. Content unique to that section is actually visible.
///   3. Content from the previously-selected section is no longer visible
///      (i.e. the pane swapped, it didn't stack).
@MainActor
final class SidebarSelectionContentUITests: MacOSUITestCase {

    // MARK: - Sidebar identifiers (source of truth: SidebarView)

    private enum SidebarID {
        static let devices = "sidebar_nav_devices"
        static let tools = "sidebar_nav_tools"
        static let settings = "sidebar_nav_settings"
    }

    // MARK: - Detail pane + content markers (source of truth: ContentView / section views)

    private enum DetailID {
        static let devicesContainer = "contentView_nav_devices"
        static let toolsContainer = "contentView_nav_tools"
        static let settingsContainer = "contentView_nav_settings"
        static let networkContainer = "contentView_nav_network"
    }

    /// Identifiers that only ever render inside a specific section. Used to
    /// assert the pane body actually populated, not just the outer container.
    private enum SectionMarker {
        /// Devices view renders a search field regardless of device count.
        static let devices = "devices_textfield_search"
        /// Tools view renders a section header for the Diagnostics category.
        static let tools = "tools_section_diagnostics"
        /// Settings view renders its tab list sidebar.
        static let settings = "settings_nav_sidebar"
        /// Network detail renders the latency card hero tile.
        static let network = "networkDetail_card_latency"
    }

    // MARK: - Helpers

    /// Tap a sidebar row and wait for the detail container to appear.
    private func selectSidebar(_ identifier: String, expectingContainer containerID: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let row = ui(identifier)
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "Sidebar row \(identifier) should exist",
                      file: file, line: line)
        row.tap()
        XCTAssertTrue(ui(containerID).waitForExistence(timeout: 5),
                      "Detail container \(containerID) should appear after selecting \(identifier)",
                      file: file, line: line)
    }

    /// Poll briefly for an accessibility ID to NOT exist in the hierarchy.
    /// Views that have been swapped out of the detail pane should disappear
    /// promptly once the new detail is on screen.
    private func assertDisappears(_ identifier: String, within timeout: TimeInterval = 3,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !ui(identifier).exists { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected \(identifier) to disappear after sidebar change, still present after \(timeout)s",
                file: file, line: line)
    }

    // MARK: - 1. Each section selection renders its section-specific content

    func testSelectingDevicesRendersDevicesContent() {
        selectSidebar(SidebarID.devices, expectingContainer: DetailID.devicesContainer)

        XCTAssertTrue(ui(SectionMarker.devices).waitForExistence(timeout: 5),
                      "Devices pane should render its search field (\(SectionMarker.devices))")

        captureScreenshot(named: "Sidebar_Select_Devices")
    }

    func testSelectingToolsRendersToolCards() {
        selectSidebar(SidebarID.tools, expectingContainer: DetailID.toolsContainer)

        XCTAssertTrue(ui(SectionMarker.tools).waitForExistence(timeout: 5),
                      "Tools pane should render the Diagnostics category header (\(SectionMarker.tools))")

        let toolCards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'tools_card_'")
        )
        XCTAssertGreaterThan(toolCards.count, 0,
                             "Tools pane should render at least one tool card")

        captureScreenshot(named: "Sidebar_Select_Tools")
    }

    func testSelectingSettingsRendersSettingsSidebar() {
        selectSidebar(SidebarID.settings, expectingContainer: DetailID.settingsContainer)

        XCTAssertTrue(ui(SectionMarker.settings).waitForExistence(timeout: 5),
                      "Settings pane should render its tab sidebar (\(SectionMarker.settings))")
        XCTAssertTrue(ui("settings_tab_General").waitForExistence(timeout: 3),
                      "Settings pane should render the General tab")

        captureScreenshot(named: "Sidebar_Select_Settings")
    }

    // MARK: - 2. Switching sections actually swaps content

    func testSwitchingFromDevicesToToolsReplacesContent() {
        selectSidebar(SidebarID.devices, expectingContainer: DetailID.devicesContainer)
        XCTAssertTrue(ui(SectionMarker.devices).waitForExistence(timeout: 5),
                      "Devices pane should be populated before switching")

        selectSidebar(SidebarID.tools, expectingContainer: DetailID.toolsContainer)
        XCTAssertTrue(ui(SectionMarker.tools).waitForExistence(timeout: 5),
                      "Tools pane should populate after switch")

        // Devices-unique search field must be gone — otherwise both panes
        // would be stacked in the hierarchy.
        assertDisappears(SectionMarker.devices)
        assertDisappears(DetailID.devicesContainer)

        captureScreenshot(named: "Sidebar_Switch_DevicesToTools")
    }

    func testSwitchingFromToolsToSettingsReplacesContent() {
        selectSidebar(SidebarID.tools, expectingContainer: DetailID.toolsContainer)
        XCTAssertTrue(ui(SectionMarker.tools).waitForExistence(timeout: 5))

        selectSidebar(SidebarID.settings, expectingContainer: DetailID.settingsContainer)
        XCTAssertTrue(ui(SectionMarker.settings).waitForExistence(timeout: 5),
                      "Settings pane should populate after switch")

        assertDisappears(SectionMarker.tools)
        assertDisappears(DetailID.toolsContainer)

        captureScreenshot(named: "Sidebar_Switch_ToolsToSettings")
    }

    func testSwitchingFromSettingsToDevicesReplacesContent() {
        selectSidebar(SidebarID.settings, expectingContainer: DetailID.settingsContainer)
        XCTAssertTrue(ui(SectionMarker.settings).waitForExistence(timeout: 5))

        selectSidebar(SidebarID.devices, expectingContainer: DetailID.devicesContainer)
        XCTAssertTrue(ui(SectionMarker.devices).waitForExistence(timeout: 5),
                      "Devices pane should populate after switch")

        assertDisappears(SectionMarker.settings)
        assertDisappears(DetailID.settingsContainer)

        captureScreenshot(named: "Sidebar_Switch_SettingsToDevices")
    }

    // MARK: - 3. Round-trip preserves the ability to re-select a section

    func testSidebarRoundTripRestoresEachSection() {
        let steps: [(sidebar: String, container: String, marker: String)] = [
            (SidebarID.devices,  DetailID.devicesContainer,  SectionMarker.devices),
            (SidebarID.tools,    DetailID.toolsContainer,    SectionMarker.tools),
            (SidebarID.settings, DetailID.settingsContainer, SectionMarker.settings),
            (SidebarID.devices,  DetailID.devicesContainer,  SectionMarker.devices),
            (SidebarID.tools,    DetailID.toolsContainer,    SectionMarker.tools)
        ]

        for (index, step) in steps.enumerated() {
            selectSidebar(step.sidebar, expectingContainer: step.container)
            XCTAssertTrue(ui(step.marker).waitForExistence(timeout: 5),
                          "Step \(index): marker \(step.marker) should appear for \(step.sidebar)")
        }

        captureScreenshot(named: "Sidebar_RoundTrip")
    }

    // MARK: - 4. Network row selection loads the Network Detail view

    func testSelectingNetworkRowShowsNetworkDetail() throws {
        // Get any network row that was auto-discovered or pre-seeded.
        let networkRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'sidebar_row_network'")
        )

        guard networkRows.firstMatch.waitForExistence(timeout: 5) else {
            // Environment couldn't auto-detect a local network. Skip rather
            // than claim a false positive.
            throw XCTSkip("No network profile discovered in UI-test environment — cannot exercise network selection path")
        }

        // Move the detail away from network first so the transition is observable.
        selectSidebar(SidebarID.tools, expectingContainer: DetailID.toolsContainer)
        assertDisappears(DetailID.networkContainer)

        // Now select the network row and expect the network detail to mount.
        networkRows.firstMatch.tap()

        XCTAssertTrue(ui(DetailID.networkContainer).waitForExistence(timeout: 5),
                      "Network detail container should appear after selecting a network row")

        // And that the tools pane's content has been replaced.
        assertDisappears(SectionMarker.tools)
        assertDisappears(DetailID.toolsContainer)

        captureScreenshot(named: "Sidebar_Select_Network")
    }
}
