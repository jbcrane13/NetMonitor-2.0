import XCTest

@MainActor
final class NetworkSwitchingUITests: MacOSUITestCase {

    func testNetworksSectionExistsInSidebar() {
        XCTAssertTrue(app.descendants(matching: .any)["sidebar_section_networks"].waitForExistence(timeout: 5),
                      "Networks section should exist in sidebar")
    }

    func testAddNetworkButtonExists() {
        XCTAssertTrue(app.buttons["sidebar_button_addNetwork"].waitForExistence(timeout: 5),
                      "Add Network button should exist in sidebar")
    }

    func testOpenAddNetworkSheet() {
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3),
                      "Add Network sheet should appear")

        let cancelButton = app.buttons["addNetwork_button_cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        cancelButton.tap()

        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3),
                      "Sheet should dismiss after cancel")
    }

    func testAddNetworkValidation() {
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

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
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))

        let gatewayField = app.textFields["addNetwork_textfield_gateway"]
        let subnetField = app.textFields["addNetwork_textfield_subnet"]
        let nameField = app.textFields["addNetwork_textfield_name"]

        clearAndTypeText("10.0.0.1", into: gatewayField)
        clearAndTypeText("10.0.0.0/24", into: subnetField)
        clearAndTypeText("Test Network", into: nameField)

        let addBarButton = app.buttons["addNetwork_button_add"]
        XCTAssertTrue(addBarButton.isEnabled)
        addBarButton.tap()

        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3),
                      "Sheet should dismiss after adding")

        XCTAssertTrue(app.staticTexts["Test Network"].waitForExistence(timeout: 3),
                      "New network should appear in sidebar")
    }

    func testSelectNetworkShowsDetail() {
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))

        clearAndTypeText("172.16.0.1", into: app.textFields["addNetwork_textfield_gateway"])
        clearAndTypeText("172.16.0.0/24", into: app.textFields["addNetwork_textfield_subnet"])

        app.buttons["addNetwork_button_add"].tap()
        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3))

        let networkItem = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '172.16'")).firstMatch
        XCTAssertTrue(networkItem.waitForExistence(timeout: 5))
        networkItem.tap()

        XCTAssertTrue(app.otherElements["contentView_nav_network"].waitForExistence(timeout: 3),
                      "Network detail view should appear after selecting a network")
    }

    func testNetworkDetailShowsCorrectInfo() {
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))

        clearAndTypeText("192.168.50.1", into: app.textFields["addNetwork_textfield_gateway"])
        clearAndTypeText("192.168.50.0/24", into: app.textFields["addNetwork_textfield_subnet"])
        clearAndTypeText("Office Network", into: app.textFields["addNetwork_textfield_name"])

        app.buttons["addNetwork_button_add"].tap()
        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3))

        let networkItem = app.staticTexts["Office Network"]
        XCTAssertTrue(networkItem.waitForExistence(timeout: 5))
        networkItem.tap()

        XCTAssertTrue(app.otherElements["networkDetail_state_inactiveNetwork"].waitForExistence(timeout: 5),
                      "A manual network should open its detail in the not-connected state")
        XCTAssertTrue(app.staticTexts["Not connected to Office Network"].exists,
                      "Detail should name the selected network")
        XCTAssertTrue(app.descendants(matching: .any)["networkDetail_section_devices"].exists,
                      "Detail should list the selected network's devices")

        // ⌘1 switches back to the local network's live dashboard.
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["networkDetail_card_isp"].waitForExistence(timeout: 5),
                      "Switching to the local network should show its live cards")
        XCTAssertFalse(app.otherElements["networkDetail_state_inactiveNetwork"].exists,
                       "The not-connected state should not show for the local network")
    }

    /// #336: a manually added network is not the one this Mac is on, so the
    /// live cards (which read the Mac's own connection) must not appear under it.
    func testManualNetworkHidesLiveDiagnostics() {
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))

        clearAndTypeText("10.236.0.1", into: app.textFields["addNetwork_textfield_gateway"])
        clearAndTypeText("10.236.0.0/24", into: app.textFields["addNetwork_textfield_subnet"])
        clearAndTypeText("Inactive Test Network", into: app.textFields["addNetwork_textfield_name"])

        app.buttons["addNetwork_button_add"].tap()
        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3))

        let networkItem = app.staticTexts["Inactive Test Network"]
        XCTAssertTrue(networkItem.waitForExistence(timeout: 5))
        networkItem.tap()

        XCTAssertTrue(app.otherElements["networkDetail_state_inactiveNetwork"].waitForExistence(timeout: 5),
                      "Inactive network should show the not-connected state")
        XCTAssertTrue(app.descendants(matching: .any)["networkDetail_section_devices"].exists,
                      "Device history stays visible for an inactive network")
        for liveCard in ["networkDetail_card_isp", "networkDetail_row_health", "networkDetail_card_latency",
                         "networkDetail_card_wifiSignal", "networkDetail_card_connectivity", "networkDetail_card_intel"] {
            XCTAssertFalse(app.descendants(matching: .any)[liveCard].exists,
                           "\(liveCard) reads this Mac's connection and must not show under an inactive network")
        }
    }

    func testSwitchBetweenNetworks() {
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))

        for i in 1...2 {
            addButton.tap()
            XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))

            clearAndTypeText("10.\(i).0.1", into: app.textFields["addNetwork_textfield_gateway"])
            clearAndTypeText("10.\(i).0.0/24", into: app.textFields["addNetwork_textfield_subnet"])
            clearAndTypeText("Network \(i)", into: app.textFields["addNetwork_textfield_name"])

            app.buttons["addNetwork_button_add"].tap()
            XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3))
        }

        let network1 = app.staticTexts["Network 1"]
        let network2 = app.staticTexts["Network 2"]

        XCTAssertTrue(network1.waitForExistence(timeout: 5))
        XCTAssertTrue(network2.waitForExistence(timeout: 5))

        network1.tap()
        XCTAssertTrue(app.otherElements["contentView_nav_network"].waitForExistence(timeout: 3))

        network2.tap()
        XCTAssertTrue(app.otherElements["contentView_nav_network"].waitForExistence(timeout: 3))
    }
}
