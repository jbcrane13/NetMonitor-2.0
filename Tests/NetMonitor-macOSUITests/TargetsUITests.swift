import XCTest

@MainActor
final class TargetsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to Targets
        let sidebar = app.staticTexts["sidebar_targets"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Detail Pane

    func testTargetsDetailExists() {
        XCTAssertTrue(app.otherElements["detail_targets"].waitForExistence(timeout: 3))
    }

    // MARK: - Toolbar Buttons

    func testAddTargetButtonExists() {
        XCTAssertTrue(app.buttons["targets_button_add"].waitForExistence(timeout: 3))
    }

    func testDeleteButtonExists() {
        XCTAssertTrue(app.buttons["targets_button_delete"].waitForExistence(timeout: 3))
    }

    func testSortMenuExists() {
        XCTAssertTrue(app.menuButtons["targets_menu_sort"].waitForExistence(timeout: 3))
    }

    // MARK: - Add Target Sheet

    func testAddTargetSheetOpens() {
        let addButton = app.buttons["targets_button_add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()

        // Verify sheet elements appear
        XCTAssertTrue(app.textFields["add_target_field_name"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["add_target_field_host"].exists)
    }

    func testAddTargetSheetHasAllFields() {
        app.buttons["targets_button_add"].tap()

        XCTAssertTrue(app.textFields["add_target_field_name"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["add_target_field_host"].exists)
        XCTAssertTrue(app.popUpButtons["add_target_picker_protocol"].exists)
        XCTAssertTrue(app.buttons["add_target_button_cancel"].exists)
        XCTAssertTrue(app.buttons["add_target_button_add"].exists)
    }

    func testAddTargetSheetCancel() {
        app.buttons["targets_button_add"].tap()

        let cancelButton = app.buttons["add_target_button_cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 3))
        cancelButton.tap()

        // Sheet should dismiss
        XCTAssertFalse(app.textFields["add_target_field_name"].waitForExistence(timeout: 2))
    }

    func testAddTargetSheetFillFields() {
        app.buttons["targets_button_add"].tap()

        let nameField = app.textFields["add_target_field_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test Server")

        let hostField = app.textFields["add_target_field_host"]
        hostField.tap()
        hostField.typeText("8.8.8.8")
    }

    // MARK: - Empty State

    func testEmptyStateOrTargetListShown() {
        XCTAssertTrue(app.otherElements["detail_targets"].waitForExistence(timeout: 3))
    }

    // MARK: - Delete Button Disabled When No Selection

    func testDeleteButtonDisabledWithNoSelection() {
        let deleteButton = app.buttons["targets_button_delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        // Delete should be disabled when no target is selected
        XCTAssertFalse(deleteButton.isEnabled)
    }
}
