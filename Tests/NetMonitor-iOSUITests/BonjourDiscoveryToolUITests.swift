import XCTest

@MainActor
final class BonjourDiscoveryToolUITests: IOSUITestCase {

    private func navigateToBonjourTool() {
        app.tabBars.buttons["Tools"].tap()
        let bonjourCard = app.otherElements["tools_card_bonjour"]
        scrollToElement(bonjourCard)
        requireExists(bonjourCard, timeout: 8, message: "Bonjour tool card should exist")
        bonjourCard.tap()
        requireExists(app.otherElements["screen_bonjourTool"], timeout: 8, message: "Bonjour tool screen should appear")
    }

    // MARK: - Screen Existence

    func testBonjourScreenExists() throws {
        navigateToBonjourTool()
        requireExists(app.otherElements["screen_bonjourTool"], message: "Bonjour screen should exist")
    }

    func testNavigationTitleExists() throws {
        navigateToBonjourTool()
        requireExists(app.navigationBars["Bonjour Discovery"], message: "Bonjour Discovery navigation bar should exist")
    }

    // MARK: - UI Elements

    func testRunButtonExists() throws {
        navigateToBonjourTool()
        requireExists(app.buttons["bonjour_button_run"], message: "Run button should exist")
    }

    // MARK: - Discovery Execution

    func testStartDiscovery() throws {
        navigateToBonjourTool()
        let runButton = requireExists(app.buttons["bonjour_button_run"], message: "Run button should exist")
        runButton.tap()

        let services = app.otherElements["bonjour_section_services"]
        let emptyState = app.otherElements["bonjour_label_noServices"]
        let discovering = app.staticTexts["Discovering services..."]
        XCTAssertTrue(
            waitForEither([services, emptyState, discovering], timeout: 10),
            "Bonjour should show discovery outcome or discovering state"
        )
    }

    func testStopDiscovery() throws {
        navigateToBonjourTool()
        let runButton = requireExists(app.buttons["bonjour_button_run"], message: "Run button should exist")
        runButton.tap()

        let discovering = app.staticTexts["Discovering services..."]
        let services = app.otherElements["bonjour_section_services"]
        let emptyState = app.otherElements["bonjour_label_noServices"]
        XCTAssertTrue(
            waitForEither([discovering, services, emptyState], timeout: 10),
            "Bonjour should enter running state"
        )

        runButton.tap()
        requireExists(app.otherElements["screen_bonjourTool"], message: "Bonjour screen should remain visible after stopping")
    }

    func testClearResultsButton() throws {
        navigateToBonjourTool()
        let runButton = requireExists(app.buttons["bonjour_button_run"], message: "Run button should exist")
        runButton.tap()

        let services = app.otherElements["bonjour_section_services"]
        let emptyState = app.otherElements["bonjour_label_noServices"]
        _ = waitForEither([services, emptyState], timeout: 10)

        runButton.tap()

        let clearButton = app.buttons["bonjour_button_clear"]
        if clearButton.waitForExistence(timeout: 3) {
            clearButton.tap()
            XCTAssertTrue(waitForDisappearance(services, timeout: 5), "Services section should disappear after clear")
        }
    }

    // MARK: - Empty State

    func testEmptyStateAfterNoResults() throws {
        navigateToBonjourTool()
        let runButton = requireExists(app.buttons["bonjour_button_run"], message: "Run button should exist")
        runButton.tap()

        let services = app.otherElements["bonjour_section_services"]
        let emptyState = app.otherElements["bonjour_label_noServices"]
        _ = waitForEither([services, emptyState], timeout: 10)

        runButton.tap()

        XCTAssertTrue(
            waitForEither([services, emptyState], timeout: 5),
            "Either services or empty state should be visible after stopping discovery"
        )
    }

    // MARK: - Service Type Picker

    func testBonjourServiceTypePickerExists() throws {
        navigateToBonjourTool()

        let pickerButton = app.buttons["bonjour_picker_serviceType"]
        let pickerElement = app.otherElements["bonjour_picker_serviceType"]
        let segmentedControl = app.segmentedControls.firstMatch

        let pickerExists = pickerButton.waitForExistence(timeout: 5)
            || pickerElement.waitForExistence(timeout: 3)
            || segmentedControl.waitForExistence(timeout: 3)

        XCTAssertTrue(pickerExists, "Bonjour service type picker or filter control should exist on the screen")
    }

    func testBonjourFilterFieldIfPresent() throws {
        navigateToBonjourTool()

        let filterField = app.textFields["bonjour_input_filter"]
        let searchField = app.searchFields.firstMatch

        let filterExists = filterField.waitForExistence(timeout: 3) || searchField.waitForExistence(timeout: 3)
        guard filterExists else { return }

        let activeField: XCUIElement = filterField.exists ? filterField : searchField
        clearAndTypeText("http", into: activeField)

        XCTAssertTrue(
            activeField.waitForExistence(timeout: 3),
            "Filter field should remain interactive after typing"
        )
    }
}
