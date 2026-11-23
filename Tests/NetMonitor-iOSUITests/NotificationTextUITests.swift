import XCTest

/// A scheduled scan's "device missing" alert, as the user sees it on the Home Screen (#453):
/// the model-worded body under "Written on device", or today's fixed text when the model
/// is unavailable.
@MainActor
final class NotificationTextUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Launches the demo, allows notifications, goes to the Home Screen and returns the
    /// alert whose text contains `expected`.
    private func deliverMissingDeviceAlert(modelAvailable: Bool, expected: String) -> XCUIElement {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--uitesting-reset", "--uitesting-notification-demo"]
        if !modelAvailable {
            app.launchArguments.append("--uitesting-model-unavailable")
        }
        app.launch()

        // The permission prompt appears on the first run on a fresh simulator only.
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
        }
        sleep(1)
        XCUIDevice.shared.press(.home)

        let alert = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 20), "The missing-device alert should appear on the Home Screen")
        return alert
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMissingDeviceAlertShowsModelTextMarkedAsWrittenOnDevice() {
        let banner = deliverMissingDeviceAlert(modelAvailable: true, expected: "dropped off your network")
        attachScreenshot("notification-model-text")
        let label = banner.label
        XCTAssertTrue(label.contains("Target Down"), "Title stays the app's text: \(label)")
        XCTAssertTrue(label.contains("Written on device"), "Subtitle marks generated text: \(label)")
        XCTAssertTrue(label.contains("dropped off your network and is not answering"), "Body is the model's text: \(label)")
    }

    func testMissingDeviceAlertKeepsTodaysTextWhenTheModelIsUnavailable() {
        let banner = deliverMissingDeviceAlert(modelAvailable: false, expected: "is not responding")
        attachScreenshot("notification-fixed-text")
        let label = banner.label
        XCTAssertTrue(label.contains("Target Down"), "Title: \(label)")
        XCTAssertTrue(label.contains("Garage Camera (192.168.1.41) is not responding"), "Fixed body: \(label)")
        XCTAssertFalse(label.contains("Written on device"), "No generated-text marker: \(label)")
    }
}
