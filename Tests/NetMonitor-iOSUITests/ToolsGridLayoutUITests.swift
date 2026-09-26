import XCTest

/// Regression coverage for #321: Tools grid cards in the right column
/// overlapping the left column.
///
/// `ToolsGridSection` lays cards out in a two-column `LazyVGrid`. This test
/// walks each row of the first section (Diagnostics) and asserts the left
/// card's trailing edge never crosses the right card's leading edge.
@MainActor
final class ToolsGridLayoutUITests: IOSUITestCase {

    func testToolsGridColumnsDoNotOverlap() {
        requireExists(app.tabBars.buttons["Tools"], message: "Tools tab should exist").tap()
        requireExists(ui("screen_tools"), timeout: 8, message: "Tools screen should appear")

        let rows: [(left: String, right: String)] = [
            ("tools_card_ping", "tools_card_traceroute"),
            ("tools_card_dns_lookup", "tools_card_whois")
        ]

        for (leftID, rightID) in rows {
            let leftCard = cardButton(prefixedBy: leftID)
            let rightCard = cardButton(prefixedBy: rightID)

            requireExists(leftCard, timeout: 8, message: "\(leftID) card should exist in tools grid")
            requireExists(rightCard, timeout: 8, message: "\(rightID) card should exist in tools grid")

            let leftFrame = leftCard.frame
            let rightFrame = rightCard.frame

            // Always logged (not just on failure) so the measured frames can be
            // read back out of the test log for before/after comparison.
            NSLog(
                "[321] %@ x=%.1f width=%.1f maxX=%.1f | %@ x=%.1f width=%.1f minX=%.1f",
                leftID, leftFrame.minX, leftFrame.width, leftFrame.maxX,
                rightID, rightFrame.minX, rightFrame.width, rightFrame.minX
            )

            XCTAssertLessThanOrEqual(
                leftFrame.maxX,
                rightFrame.minX,
                "\(leftID) (x: \(leftFrame.minX), width: \(leftFrame.width), maxX: \(leftFrame.maxX)) "
                    + "should not overlap \(rightID) (x: \(rightFrame.minX), width: \(rightFrame.width))"
            )
        }

        captureScreenshot(named: "tools_grid_\(UIDevice.current.name)")
    }

    // MARK: - Helpers

    private func ui(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// On iOS 26, NavigationLink card buttons carry a synthesised identifier
    /// (e.g. "tools_card_ping-tools_card_ping-<uuid>"), so match by prefix
    /// rather than exact identifier equality.
    private func cardButton(prefixedBy prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }
}
