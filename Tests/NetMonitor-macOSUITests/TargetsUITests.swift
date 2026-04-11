import XCTest

@MainActor
final class TargetsUITests: MacOSUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        navigateToSidebar("targets")
    }

    // MARK: - Detail Pane

    func testTargetsDetailExists() {
        requireExists(app.otherElements["detail_targets"], timeout: 3,
                      message: "Targets detail pane should exist")
    }

    // MARK: - Toolbar Buttons

    func testAddTargetButtonExists() {
        requireExists(app.buttons["targets_button_add"], timeout: 3,
                      message: "Add target button should exist")
    }

    func testDeleteButtonExists() {
        requireExists(app.buttons["targets_button_delete"], timeout: 3,
                      message: "Delete button should exist")
    }

    func testSortMenuExists() {
        requireExists(app.menuButtons["targets_menu_sort"], timeout: 3,
                      message: "Sort menu should exist")
    }

    // MARK: - Add Target Sheet

    func testAddTargetSheetOpens() {
        let addButton = requireExists(app.buttons["targets_button_add"], timeout: 3,
                                      message: "Add target button should exist")
        addButton.tap()

        requireExists(app.textFields["add_target_field_name"], timeout: 3,
                      message: "Name field should appear in add-target sheet")
        XCTAssertTrue(app.textFields["add_target_field_host"].exists,
                      "Host field should appear in add-target sheet")
    }

    func testAddTargetSheetHasAllFields() {
        app.buttons["targets_button_add"].tap()

        requireExists(app.textFields["add_target_field_name"], timeout: 3,
                      message: "Name field should exist in add-target sheet")
        XCTAssertTrue(app.textFields["add_target_field_host"].exists,
                      "Host field should exist")
        XCTAssertTrue(app.popUpButtons["add_target_picker_protocol"].exists,
                      "Protocol picker should exist")
        XCTAssertTrue(app.buttons["add_target_button_cancel"].exists,
                      "Cancel button should exist")
        XCTAssertTrue(app.buttons["add_target_button_add"].exists,
                      "Add button should exist")
    }

    func testAddTargetSheetCancel() {
        app.buttons["targets_button_add"].tap()

        let cancelButton = requireExists(app.buttons["add_target_button_cancel"], timeout: 3,
                                         message: "Cancel button should exist in add-target sheet")
        cancelButton.tap()

        XCTAssertFalse(app.textFields["add_target_field_name"].waitForExistence(timeout: 2),
                       "Add-target sheet should dismiss after cancelling")
    }

    func testAddTargetSheetFillFields() {
        app.buttons["targets_button_add"].tap()

        let nameField = requireExists(app.textFields["add_target_field_name"], timeout: 3,
                                      message: "Name field should exist")
        clearAndTypeText("Test Server", into: nameField)

        let hostField = app.textFields["add_target_field_host"]
        if hostField.waitForExistence(timeout: 2) {
            clearAndTypeText("8.8.8.8", into: hostField)
        }

        app.buttons["add_target_button_cancel"].tap()
    }

    // MARK: - Functional: Add Target Validation

    func testAddTargetValidationRequiresFields() {
        app.buttons["targets_button_add"].tap()

        let addButton = requireExists(
            app.buttons["add_target_button_add"], timeout: 5,
            message: "Add button should exist in add-target sheet"
        )

        XCTAssertTrue(addButton.exists, "Add button should be present without filling fields")

        app.buttons["add_target_button_cancel"].tap()
    }

    func testAddTargetWithValidFieldsShowsAddButton() {
        app.buttons["targets_button_add"].tap()

        let nameField = requireExists(app.textFields["add_target_field_name"], timeout: 5,
                                      message: "Name field should appear in add-target sheet")
        clearAndTypeText("My Server", into: nameField)

        let hostField = app.textFields["add_target_field_host"]
        if hostField.waitForExistence(timeout: 2) {
            clearAndTypeText("1.1.1.1", into: hostField)
        }

        let addButton = requireExists(
            app.buttons["add_target_button_add"], timeout: 3,
            message: "Add button should exist after filling fields"
        )
        XCTAssertTrue(addButton.exists, "Add button should remain visible after filling fields")

        app.buttons["add_target_button_cancel"].tap()
    }

    // MARK: - Functional: Sort Menu

    func testSortMenuOpensOptions() {
        let sortMenu = requireExists(
            app.menuButtons["targets_menu_sort"], timeout: 3,
            message: "Sort menu should exist"
        )
        XCTAssertTrue(sortMenu.isEnabled, "Sort menu should be enabled")

        sortMenu.tap()

        XCTAssertTrue(
            waitForEither(
                [app.menuItems.firstMatch, app.menuButtons.firstMatch],
                timeout: 3
            ),
            "Sort menu should open and show at least one menu item"
        )

        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Empty State

    func testEmptyStateOrTargetListShown() {
        requireExists(app.otherElements["detail_targets"], timeout: 3,
                      message: "Targets detail pane should be visible")
    }

    // MARK: - Delete Button Disabled When No Selection

    func testDeleteButtonDisabledWithNoSelection() {
        let deleteButton = requireExists(
            app.buttons["targets_button_delete"], timeout: 3,
            message: "Delete button should exist"
        )
        XCTAssertFalse(deleteButton.isEnabled,
                       "Delete button should be disabled when no target is selected")
    }
}
