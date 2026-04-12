import Testing
@testable import NetMonitor_macOS

@MainActor
struct WakeOnLanActionTests {

    @Test func initialShowAlertIsFalse() {
        let action = WakeOnLanAction()
        #expect(!action.showAlert)
    }

    @Test func initialAlertMessageIsNil() {
        let action = WakeOnLanAction()
        #expect(action.alertMessage == nil)
    }

    @Test func dismissAlertHidesAlert() {
        let action = WakeOnLanAction()
        action.showAlert = true
        action.dismissAlert()
        #expect(!action.showAlert)
    }

    @Test func dismissAlertKeepsMessageNil() {
        let action = WakeOnLanAction()
        action.dismissAlert()
        #expect(action.alertMessage == nil)
    }

    @Test func dismissAlertIsIdempotent() {
        let action = WakeOnLanAction()
        action.showAlert = true
        action.dismissAlert()
        action.dismissAlert()
        #expect(!action.showAlert)
        #expect(action.alertMessage == nil)
    }
}
