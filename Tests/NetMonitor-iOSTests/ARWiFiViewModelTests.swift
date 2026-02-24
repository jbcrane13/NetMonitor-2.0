import Testing
import Foundation
@testable import NetMonitor_iOS

// MARK: - ARWiFiViewModel Tests

@Suite("ARWiFiViewModel")
@MainActor
struct ARWiFiViewModelTests {

    // MARK: - Initialization

    @Test("initial signal strength is reasonable default")
    func initialSignalDBm() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        // Default is -65 dBm (mid-range "Good" signal)
        #expect(vm.signalDBm == -65)
    }

    @Test("initial signal quality is 0.5")
    func initialSignalQuality() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        #expect(vm.signalQuality == 0.5)
    }

    @Test("isSessionRunning starts false")
    func isSessionRunningInitiallyFalse() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        #expect(vm.isSessionRunning == false)
    }

    @Test("errorMessage starts nil")
    func errorMessageInitiallyNil() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        #expect(vm.errorMessage == nil)
    }

    @Test("ssid starts nil")
    func ssidInitiallyNil() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        #expect(vm.ssid == nil)
    }

    @Test("bssid starts nil")
    func bssidInitiallyNil() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        #expect(vm.bssid == nil)
    }

    // MARK: - AR Support Detection

    @Test("isARSupported reflects ARWiFiSession.isSupported")
    func isARSupportedMatchesSession() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        #expect(vm.isARSupported == ARWiFiSession.isSupported)
    }

    // MARK: - Signal Color

    @Test("signalColor is green above -50 dBm")
    func signalColorGreenAboveMinus50() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        vm.signalDBm = -40
        let color = vm.signalColor
        // Green should be Color.green (RGB roughly 0, 1, 0)
        #expect("\(color)".lowercased().contains("green") || color == .green)
    }

    @Test("signalColor is yellow between -50 and -70 dBm")
    func signalColorYellowMidRange() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        vm.signalDBm = -60
        let color = vm.signalColor
        #expect("\(color)".lowercased().contains("yellow") || color == .yellow)
    }

    @Test("signalColor is red below -70 dBm")
    func signalColorRedBelowMinus70() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        vm.signalDBm = -80
        let color = vm.signalColor
        #expect("\(color)".lowercased().contains("red") || color == .red)
    }

    // MARK: - Signal Labels

    @Test("signalLabel is Excellent above -50 dBm")
    func signalLabelExcellent() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        vm.signalDBm = -45
        #expect(vm.signalLabel == "Excellent")
    }

    @Test("signalLabel is Good between -50 and -70 dBm")
    func signalLabelGood() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        vm.signalDBm = -60
        #expect(vm.signalLabel == "Good")
    }

    @Test("signalLabel is Fair between -70 and -85 dBm")
    func signalLabelFair() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        vm.signalDBm = -78
        #expect(vm.signalLabel == "Fair")
    }

    @Test("signalLabel is Poor below -85 dBm")
    func signalLabelPoor() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        vm.signalDBm = -90
        #expect(vm.signalLabel == "Poor")
    }

    // MARK: - No-AR Fallback

    @Test("startSession sets errorMessage when AR not supported")
    func startSessionErrorWhenNotSupported() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        // On simulator/macOS, ARWiFiSession.isSupported is false
        if !vm.isARSupported {
            vm.startSession()
            #expect(vm.errorMessage != nil)
            #expect(vm.isSessionRunning == false)
        }
    }

    @Test("stopSession sets isSessionRunning to false")
    func stopSessionSetsRunningFalse() {
        let vm = ARWiFiViewModel(arSession: ARWiFiSession())
        vm.isSessionRunning = true
        vm.stopSession()
        #expect(vm.isSessionRunning == false)
    }
}
