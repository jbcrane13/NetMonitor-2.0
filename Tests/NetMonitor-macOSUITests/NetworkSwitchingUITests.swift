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

        let cancelButton = app.buttons["add_network_button_cancel"]
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

        let gatewayField = app.textFields["add_network_field_gateway"]
        let subnetField = app.textFields["add_network_field_subnet"]
        let addBarButton = app.buttons["add_network_button_add"]

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

        app.buttons["add_network_button_cancel"].tap()
    }

    func testAddNetworkSuccessfully() {
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))

        let gatewayField = app.textFields["add_network_field_gateway"]
        let subnetField = app.textFields["add_network_field_subnet"]
        let nameField = app.textFields["add_network_field_name"]

        clearAndTypeText("10.0.0.1", into: gatewayField)
        clearAndTypeText("10.0.0.0/24", into: subnetField)
        clearAndTypeText("Test Network", into: nameField)

        let addBarButton = app.buttons["add_network_button_add"]
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

        clearAndTypeText("172.16.0.1", into: app.textFields["add_network_field_gateway"])
        clearAndTypeText("172.16.0.0/24", into: app.textFields["add_network_field_subnet"])

        app.buttons["add_network_button_add"].tap()
        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3))

        let networkItem = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '172.16'")).firstMatch
        XCTAssertTrue(networkItem.waitForExistence(timeout: 5))
        networkItem.tap()

        XCTAssertTrue(app.otherElements["network_detail_view"].waitForExistence(timeout: 3),
                      "Network detail view should appear after selecting a network")
    }

    func testNetworkDetailShowsCorrectInfo() {
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))

        clearAndTypeText("192.168.50.1", into: app.textFields["add_network_field_gateway"])
        clearAndTypeText("192.168.50.0/24", into: app.textFields["add_network_field_subnet"])
        clearAndTypeText("Office Network", into: app.textFields["add_network_field_name"])

        app.buttons["add_network_button_add"].tap()
        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3))

        let networkItem = app.staticTexts["Office Network"]
        XCTAssertTrue(networkItem.waitForExistence(timeout: 5))
        networkItem.tap()

        XCTAssertTrue(app.otherElements["network_detail_card_header"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["network_detail_card_networkInfo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["network_detail_card_discovery"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["network_detail_card_devices"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["network_detail_button_scan"].waitForExistence(timeout: 3))
    }

    func testSwitchBetweenNetworks() {
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))

        for i in 1...2 {
            addButton.tap()
            XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))

            clearAndTypeText("10.\(i).0.1", into: app.textFields["add_network_field_gateway"])
            clearAndTypeText("10.\(i).0.0/24", into: app.textFields["add_network_field_subnet"])
            clearAndTypeText("Network \(i)", into: app.textFields["add_network_field_name"])

            app.buttons["add_network_button_add"].tap()
            XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3))
        }

        let network1 = app.staticTexts["Network 1"]
        let network2 = app.staticTexts["Network 2"]

        XCTAssertTrue(network1.waitForExistence(timeout: 5))
        XCTAssertTrue(network2.waitForExistence(timeout: 5))

        network1.tap()
        XCTAssertTrue(app.otherElements["network_detail_view"].waitForExistence(timeout: 3))

        network2.tap()
        XCTAssertTrue(app.otherElements["network_detail_view"].waitForExistence(timeout: 3))
    }

    func testScanButtonFromNetworkDetail() {
        let addButton = app.buttons["sidebar_button_addNetwork"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3))

        clearAndTypeText("192.168.100.1", into: app.textFields["add_network_field_gateway"])
        clearAndTypeText("192.168.100.0/24", into: app.textFields["add_network_field_subnet"])

        app.buttons["add_network_button_add"].tap()
        XCTAssertTrue(waitForDisappearance(app.sheets.firstMatch, timeout: 3))

        let networkItem = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '192.168.100'")).firstMatch
        XCTAssertTrue(networkItem.waitForExistence(timeout: 5))
        networkItem.tap()

        let scanButton = app.buttons["network_detail_button_scan"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 3))
        scanButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["sidebar_nav_devices"].waitForExistence(timeout: 3),
                      "Should navigate to devices after initiating scan")
    }
}
