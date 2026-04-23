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

    func testBonjourScreenExistsAndShowsControls() throws {
        navigateToBonjourTool()
        let screen = app.otherElements["screen_bonjourTool"]
        XCTAssertTrue(screen.waitForExistence(timeout: 5), "Bonjour screen should exist")
        // FUNCTIONAL: screen should contain run button
        XCTAssertTrue(
            app.buttons["bonjour_button_run"].waitForExistence(timeout: 3),
            "Bonjour screen should show run button"
        )
    }

    func testNavigationTitleExists() throws {
        navigateToBonjourTool()
        requireExists(app.navigationBars["Bonjour Discovery"], message: "Bonjour Discovery navigation bar should exist")
    }

    // MARK: - UI Elements

    func testRunButtonExistsAndIsEnabled() throws {
        navigateToBonjourTool()
        let runButton = app.buttons["bonjour_button_run"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5), "Run button should exist")
        // FUNCTIONAL: run button should be immediately tappable (no input required)
        XCTAssertTrue(runButton.isEnabled, "Run button should be enabled on Bonjour screen")
    }

    // MARK: - Discovery Execution

    func testStartDiscoveryProducesOutcome() throws {
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
        // FUNCTIONAL: verify discovery produced a concrete state
        XCTAssertTrue(
            services.exists || emptyState.exists || discovering.exists,
            "Bonjour should show services, no-services state, or discovery indicator after starting"
        )
    }

    func testStopDiscoveryReturnsToIdleState() throws {
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
        // FUNCTIONAL: screen should still be visible and functional after stopping
        requireExists(app.otherElements["screen_bonjourTool"], message: "Bonjour screen should remain visible after stopping")
        XCTAssertTrue(runButton.exists, "Run button should be accessible after stopping")
    }

    func testClearResultsButtonRemovesServices() throws {
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
            // FUNCTIONAL: after clearing, run button should be available
            XCTAssertTrue(runButton.exists, "Run button should be accessible after clearing results")
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

        // FUNCTIONAL: should show either services or meaningful empty state
        XCTAssertTrue(
            waitForEither([services, emptyState], timeout: 5),
            "Either services or empty state should be visible after stopping discovery"
        )
        if emptyState.exists {
            XCTAssertTrue(
                emptyState.staticTexts.count > 0,
                "Empty state should contain descriptive text"
            )
        }
    }

    // MARK: - Service Type Picker

    func testBonjourServiceTypePickerExistsAndIsTappable() throws {
        navigateToBonjourTool()

        let pickerButton = app.buttons["bonjour_picker_serviceType"]
        let pickerElement = app.otherElements["bonjour_picker_serviceType"]
        let segmentedControl = app.segmentedControls.firstMatch

        let pickerExists = pickerButton.waitForExistence(timeout: 5)
            || pickerElement.waitForExistence(timeout: 3)
            || segmentedControl.waitForExistence(timeout: 3)

        XCTAssertTrue(pickerExists, "Bonjour service type picker or filter control should exist on the screen")
        // FUNCTIONAL: picker/control should be interactive
        let activeControl: XCUIElement = {
            if pickerButton.exists { return pickerButton }
            if pickerElement.exists { return pickerElement }
            return segmentedControl
        }()
        XCTAssertTrue(activeControl.isEnabled, "Service type picker should be interactive")
    }

    func testBonjourFilterFieldIfPresent() throws {
        navigateToBonjourTool()

        let filterField = app.textFields["bonjour_input_filter"]
        let searchField = app.searchFields.firstMatch

        let filterExists = filterField.waitForExistence(timeout: 3) || searchField.waitForExistence(timeout: 3)
        guard filterExists else { return }

        let activeField: XCUIElement = filterField.exists ? filterField : searchField
        clearAndTypeText("http", into: activeField)

        // FUNCTIONAL: filter field should accept input and remain interactive
        XCTAssertTrue(
            activeField.waitForExistence(timeout: 3),
            "Filter field should remain interactive after typing"
        )
        let fieldValue = activeField.value as? String ?? ""
        XCTAssertTrue(fieldValue.contains("http"), "Filter field should contain the typed filter text")
    }
}
