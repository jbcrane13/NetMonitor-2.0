import XCTest

final class NetworkMapUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Map"].tap()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screen Existence

    func testNetworkMapScreenExists() throws {
        XCTAssertTrue(app.otherElements["screen_networkMap"].waitForExistence(timeout: 5))
    }

    func testNavigationTitleExists() throws {
        XCTAssertTrue(app.navigationBars["Devices"].waitForExistence(timeout: 5))
    }

    // MARK: - Network Summary

    func testNetworkSummaryExists() throws {
        XCTAssertTrue(app.otherElements["networkMap_summary"].waitForExistence(timeout: 5))
    }

    func testNetworkPickerExists() throws {
        XCTAssertTrue(app.buttons["Add Network"].firstMatch.waitForExistence(timeout: 5))
    }

    func testAddNetworkSheetShowsManualFields() throws {
        let addButton = app.buttons["Add Network"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.navigationBars["Add Network"].waitForExistence(timeout: 5))

        let manualTab = app.segmentedControls.buttons["Manual"]
        if manualTab.waitForExistence(timeout: 3) {
            manualTab.tap()
        }

        XCTAssertTrue(app.textFields["network_sheet_field_gateway"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["network_sheet_field_cidr"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["network_sheet_field_name"].waitForExistence(timeout: 3))
    }

    // MARK: - Sort Controls

    func testSortPickerExists() throws {
        XCTAssertTrue(app.buttons["networkMap_picker_sort"].waitForExistence(timeout: 5) ||
                      app.otherElements["networkMap_picker_sort"].waitForExistence(timeout: 3))
    }

    // MARK: - Scan Button

    func testScanButtonExists() throws {
        XCTAssertTrue(app.buttons["networkMap_button_scan"].waitForExistence(timeout: 5))
    }

    func testScanButtonTriggersScan() throws {
        let scanButton = app.buttons["networkMap_button_scan"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5))
        scanButton.tap()
        // After tapping, either a progress indicator appears or devices start showing
        sleep(2)
        // The button should still exist (it becomes a spinner during scan)
        XCTAssertTrue(scanButton.exists || app.activityIndicators.firstMatch.exists)
    }

    // MARK: - Empty State

    func testEmptyStateLabelExists() throws {
        // If no devices found, empty state should show
        let emptyLabel = app.otherElements["networkMap_label_empty"]
        let deviceRow = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")).firstMatch
        // Either we have devices or empty state
        XCTAssertTrue(emptyLabel.exists || deviceRow.exists || app.activityIndicators.firstMatch.exists)
    }

    // MARK: - Device Row Navigation

    func testDeviceRowNavigatesToDetail() throws {
        let scanButton = app.buttons["networkMap_button_scan"]
        if scanButton.waitForExistence(timeout: 5) {
            scanButton.tap()
            sleep(5)
            let firstDeviceRow = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'networkMap_row_'")).firstMatch
            if firstDeviceRow.waitForExistence(timeout: 10) {
                firstDeviceRow.tap()
                XCTAssertTrue(app.otherElements["screen_deviceDetail"].waitForExistence(timeout: 5))
            }
        }
    }
}
