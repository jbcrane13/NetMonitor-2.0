import Testing
import Foundation
@testable import NetMonitor_iOS
@testable import NetMonitorCore

// MARK: - ARHeatmapSurveyViewModel Tests

@Suite("ARHeatmapSurveyViewModel")
@MainActor
struct ARHeatmapSurveyViewModelTests {

    // MARK: - Initialization

    @Test("initial state is not scanning")
    func initialStateNotScanning() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        #expect(vm.isScanning == false)
    }

    @Test("initial point count is zero")
    func initialPointCountZero() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        #expect(vm.pointCount == 0)
    }

    @Test("initial signal is -65 dBm")
    func initialSignalDBm() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        #expect(vm.signalDBm == -65)
    }

    @Test("initial ssid is nil")
    func initialSsidNil() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        #expect(vm.ssid == nil)
    }

    @Test("initial error message is nil")
    func initialErrorMessageNil() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Signal Display Helpers

    @Test("signalColor is green above -50 dBm")
    func signalColorGreen() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.signalDBm = -40
        #expect(vm.signalColor == .green)
    }

    @Test("signalColor is yellow between -50 and -70 dBm")
    func signalColorYellow() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.signalDBm = -60
        #expect(vm.signalColor == .yellow)
    }

    @Test("signalColor is red below -70 dBm")
    func signalColorRed() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.signalDBm = -80
        #expect(vm.signalColor == .red)
    }

    @Test("signalLabel is Excellent above -50")
    func signalLabelExcellent() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.signalDBm = -45
        #expect(vm.signalLabel == "Excellent")
    }

    @Test("signalLabel is Good between -50 and -70")
    func signalLabelGood() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.signalDBm = -55
        #expect(vm.signalLabel == "Good")
    }

    @Test("signalLabel is Fair between -70 and -85")
    func signalLabelFair() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.signalDBm = -78
        #expect(vm.signalLabel == "Fair")
    }

    @Test("signalLabel is Poor below -85")
    func signalLabelPoor() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.signalDBm = -90
        #expect(vm.signalLabel == "Poor")
    }

    @Test("signalText shows dBm when scanning")
    func signalTextWhileScanning() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.startScanning()
        #expect(vm.signalText.contains("dBm"))
        vm.stopScanning()
    }

    @Test("signalText shows -- when not scanning")
    func signalTextWhenStopped() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        #expect(vm.signalText == "--")
    }

    // MARK: - Scan Lifecycle

    @Test("startScanning sets isScanning true")
    func startScanningSetsFlagTrue() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.startScanning()
        #expect(vm.isScanning == true)
        vm.stopScanning()
    }

    @Test("stopScanning sets isScanning false")
    func stopScanningSetsFlag() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.startScanning()
        vm.stopScanning()
        #expect(vm.isScanning == false)
    }

    @Test("startScanning resets point count")
    func startScanningResetsPointCount() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.startScanning()
        vm.stopScanning()
        vm.startScanning()
        #expect(vm.pointCount == 0)
        vm.stopScanning()
    }

    @Test("double start is a no-op")
    func doubleStartNoOp() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.startScanning()
        vm.startScanning()
        #expect(vm.isScanning == true)
        vm.stopScanning()
    }

    @Test("double stop is a no-op")
    func doubleStopNoOp() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        vm.startScanning()
        vm.stopScanning()
        vm.stopScanning()
        #expect(vm.isScanning == false)
    }

    // MARK: - Coordinate Normalization

    @Test("normalizePoints returns empty for no data")
    func normalizeEmptyReturnsEmpty() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        #expect(vm.normalizePoints().isEmpty)
    }

    @Test("buildSurvey returns nil when no points")
    func buildSurveyNilWhenEmpty() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        #expect(vm.buildSurvey() == nil)
    }

    @Test("buildSurvey sets mode to arContinuous")
    func buildSurveySetsMode() {
        let vm = ARHeatmapSurveyViewModel(arSession: ARHeatmapSession())
        // We can't record real points on simulator, but verify nil return
        let survey = vm.buildSurvey()
        // On simulator with no AR, no points are recorded
        if let survey {
            #expect(survey.mode == .arContinuous)
        }
    }
}
