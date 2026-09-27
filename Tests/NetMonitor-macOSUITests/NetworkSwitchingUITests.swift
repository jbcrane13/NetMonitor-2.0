import XCTest

@MainActor
final class NetworkSwitchingUITests: MacOSUITestCase {

    // MARK: - Helpers

    /// On macOS 27 the NETWORKS section header can be exposed as one element
    /// labelled "NETWORKS, Add" carrying the + button's identifier; the + sits
    /// at its trailing edge.
    private func tapAddNetwork() {
        let add = ui("sidebar_button_addNetwork").firstMatch
        requireExists(add, timeout: 5, message: "Add Network control should exist in sidebar")
        if add.elementType == .button {
            add.tap()
        } else {
            add.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        }
    }

    private func addNetwork(gateway: String, subnet: String, name: String? = nil) {
        tapAddNetwork()
        requireExists(app.sheets.firstMatch, timeout: 3, message: "Add Network sheet should appear")

        clearAndTypeText(gateway, into: app.textFields["addNetwork_textfield_gateway"])
        clearAndTypeText(subnet, into: app.textFields["addNetwork_textfield_subnet"])
        if let name {
            clearAndTypeText(name, into: app.textFields["addNetwork_textfield_name"])
        }

        app.buttons["addNetwork_button_add"].tap()
        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3),
                      "Sheet should dismiss after adding")
    }

    /// The sidebar row for the network with this exact name.
    private func sidebarRow(named name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'sidebar_row_network' AND (label == %@ OR value == %@)", name, name
        )).firstMatch
    }

    /// The not-connected banner shown for a network this Mac is not on.
    private func notConnectedText(for name: String) -> XCUIElement {
        let text = "Not connected to \(name)"
        return app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).firstMatch
    }

    // MARK: - Tests

    func testNetworksSectionListsLocalNetwork() {
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'sidebar_row_network'")
        )
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5),
                      "Networks section should list at least the local network")
        let activeBadge = rows.matching(NSPredicate(format: "label == 'ACTIVE' OR value == 'ACTIVE'")).firstMatch
        XCTAssertTrue(activeBadge.exists, "One network row should carry the ACTIVE badge")
    }

    func testOpenAddNetworkSheet() {
        tapAddNetwork()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3),
                      "Add Network sheet should appear")

        let cancelButton = app.buttons["addNetwork_button_cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        cancelButton.tap()

        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3),
                      "Sheet should dismiss after cancel")
    }

    func testAddNetworkValidation() {
        tapAddNetwork()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))

        let gatewayField = app.textFields["addNetwork_textfield_gateway"]
        let subnetField = app.textFields["addNetwork_textfield_subnet"]
        let addBarButton = app.buttons["addNetwork_button_add"]

        XCTAssertTrue(gatewayField.waitForExistence(timeout: 3))
        XCTAssertTrue(subnetField.waitForExistence(timeout: 3))
        XCTAssertTrue(addBarButton.waitForExistence(timeout: 3))

        XCTAssertFalse(addBarButton.isEnabled, "Add button should be disabled initially")

        clearAndTypeText("invalid", into: gatewayField)
        XCTAssertFalse(addBarButton.isEnabled, "Add button should be disabled with invalid IP")

        clearAndTypeText("192.168.1.1", into: gatewayField)
        XCTAssertFalse(addBarButton.isEnabled, "Add button should be disabled without subnet")

        clearAndTypeText("192.168.1.0/24", into: subnetField)
        XCTAssertTrue(addBarButton.isEnabled, "Add button should be enabled with valid input")

        app.buttons["addNetwork_button_cancel"].tap()
    }

    func testAddNetworkSuccessfully() {
        addNetwork(gateway: "10.0.0.1", subnet: "10.0.0.0/24", name: "Test Network")

        XCTAssertTrue(sidebarRow(named: "Test Network").waitForExistence(timeout: 3),
                      "New network should appear in sidebar")
    }

    func testSelectNetworkShowsDetail() {
        // Unnamed networks are named after their subnet.
        addNetwork(gateway: "172.16.0.1", subnet: "172.16.0.0/24")

        let networkItem = sidebarRow(named: "Network 172.16.0.0/24")
        XCTAssertTrue(networkItem.waitForExistence(timeout: 5))
        networkItem.tap()

        XCTAssertTrue(notConnectedText(for: "Network 172.16.0.0/24").waitForExistence(timeout: 5),
                      "Selecting a network should show that network's detail")
    }

    func testNetworkDetailShowsCorrectInfo() {
        addNetwork(gateway: "192.168.50.1", subnet: "192.168.50.0/24", name: "Office Network")

        let networkItem = sidebarRow(named: "Office Network")
        XCTAssertTrue(networkItem.waitForExistence(timeout: 5))
        networkItem.tap()

        XCTAssertTrue(ui("networkDetail_state_inactiveNetwork").waitForExistence(timeout: 5),
                      "A manual network should open its detail in the not-connected state")
        XCTAssertTrue(notConnectedText(for: "Office Network").exists,
                      "Detail should name the selected network")
        XCTAssertTrue(ui("networkDetail_section_devices").exists,
                      "Detail should list the selected network's devices")

        // ⌘1 switches back to the local network's live dashboard.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(ui("networkDetail_card_isp").waitForExistence(timeout: 5),
                      "Switching to the local network should show its live cards")
        XCTAssertFalse(ui("networkDetail_state_inactiveNetwork").exists,
                       "The not-connected state should not show for the local network")
    }

    /// #336: a manually added network is not the one this Mac is on, so the
    /// live cards (which read the Mac's own connection) must not appear under it.
    func testManualNetworkHidesLiveDiagnostics() {
        addNetwork(gateway: "10.236.0.1", subnet: "10.236.0.0/24", name: "Inactive Test Network")

        let networkItem = sidebarRow(named: "Inactive Test Network")
        XCTAssertTrue(networkItem.waitForExistence(timeout: 5))
        networkItem.tap()

        XCTAssertTrue(ui("networkDetail_state_inactiveNetwork").waitForExistence(timeout: 5),
                      "Inactive network should show the not-connected state")
        XCTAssertTrue(ui("networkDetail_section_devices").exists,
                      "Device history stays visible for an inactive network")
        for liveCard in ["networkDetail_card_isp", "networkDetail_row_health", "networkDetail_card_latency",
                         "networkDetail_card_wifiSignal", "networkDetail_card_connectivity", "networkDetail_card_intel"] {
            XCTAssertFalse(ui(liveCard).exists,
                           "\(liveCard) reads this Mac's connection and must not show under an inactive network")
        }
    }

    func testSwitchBetweenNetworks() {
        for i in 1...2 {
            addNetwork(gateway: "10.\(i).0.1", subnet: "10.\(i).0.0/24", name: "Network \(i)")
        }

        let network1 = sidebarRow(named: "Network 1")
        let network2 = sidebarRow(named: "Network 2")

        XCTAssertTrue(network1.waitForExistence(timeout: 5))
        XCTAssertTrue(network2.waitForExistence(timeout: 5))

        network1.tap()
        XCTAssertTrue(notConnectedText(for: "Network 1").waitForExistence(timeout: 5),
                      "Detail should show Network 1")

        network2.tap()
        XCTAssertTrue(notConnectedText(for: "Network 2").waitForExistence(timeout: 5),
                      "Detail should switch to Network 2")
        XCTAssertFalse(notConnectedText(for: "Network 1").exists,
                       "Network 1's detail should be replaced")
    }
}
