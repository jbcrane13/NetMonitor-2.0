import Testing
import Foundation
@testable import NetMonitor_iOS
@testable import NetMonitorCore

// MARK: - ARContinuousHeatmapViewModel Tests

@Suite("ARContinuousHeatmapViewModel")
@MainActor
struct ARContinuousHeatmapViewModelTests {

    // MARK: - Initial state

    @Test("initial isScanning is false")
    func initialNotScanning() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.isScanning == false)
    }

    @Test("initial floorDetected is false")
    func initialFloorNotDetected() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.floorDetected == false)
    }

    @Test("initial pointCount is 0")
    func initialPointCount() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.pointCount == 0)
    }

    @Test("initial signalDBm is -65")
    func initialSignal() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.signalDBm == -65)
    }

    @Test("initial ssid is nil")
    func initialSSID() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.ssid == nil)
    }

    @Test("initial bssid is nil")
    func initialBSSID() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.bssid == nil)
    }

    @Test("initial errorMessage is nil")
    func initialError() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Signal display helpers

    @Test("signalColor is green above -50 dBm")
    func signalColorGreen() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.signalDBm = -40
        #expect(vm.signalColor == .green)
    }

    @Test("signalColor is yellow between -50 and -70 dBm")
    func signalColorYellow() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.signalDBm = -60
        #expect(vm.signalColor == .yellow)
    }

    @Test("signalColor is red at -70 dBm or below")
    func signalColorRed() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.signalDBm = -80
        #expect(vm.signalColor == .red)
    }

    @Test("signalText shows dBm when scanning")
    func signalTextScanning() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.isScanning = true
        vm.signalDBm = -55
        #expect(vm.signalText == "-55 dBm")
    }

    @Test("signalText shows -- when not scanning")
    func signalTextNotScanning() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.signalText == "--")
    }

    // MARK: - Scan lifecycle (simulator — AR session stub returns nil position)

    @Test("startScanning sets isScanning true")
    func startSetsScanning() async {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.startScanning()
        #expect(vm.isScanning == true)
    }

    @Test("stopScanning sets isScanning false")
    func stopSetsNotScanning() async {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.startScanning()
        vm.stopScanning()
        #expect(vm.isScanning == false)
    }

    @Test("double start is a no-op")
    func doubleStart() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.startScanning()
        vm.startScanning()
        #expect(vm.isScanning == true)
    }

    @Test("double stop is a no-op")
    func doubleStop() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.stopScanning()
        #expect(vm.isScanning == false)
    }

    @Test("startScanning resets grid state")
    func startResetsGrid() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        // Pre-populate a cell
        vm.gridState[5][5] = -60
        vm.startScanning()
        #expect(vm.gridState[5][5] == nil)
    }

    // MARK: - buildSurvey

    @Test("buildSurvey with no points returns nil")
    func buildSurveyEmpty() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.buildSurvey() == nil)
    }

    @Test("buildSurvey with points returns arContinuous mode survey")
    func buildSurveyMode() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.injectWorldPoint(x: 0.0, z: 0.0, rssi: -60)
        vm.injectWorldPoint(x: 1.0, z: 1.0, rssi: -70)
        let survey = vm.buildSurvey()
        #expect(survey != nil)
        #expect(survey?.mode == .arContinuous)
    }

    @Test("buildSurvey normalizes points to 0-1 range")
    func buildSurveyNormalized() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.injectWorldPoint(x: 0.0, z: 0.0, rssi: -60)
        vm.injectWorldPoint(x: 4.0, z: 4.0, rssi: -70)
        let survey = vm.buildSurvey()!
        let xs = survey.dataPoints.map(\.x)
        let ys = survey.dataPoints.map(\.y)
        #expect(xs.min()! >= 0.0)
        #expect(xs.max()! <= 1.0)
        #expect(ys.min()! >= 0.0)
        #expect(ys.max()! <= 1.0)
    }

    // MARK: - Grid texture rendering

    @Test("renderGridTexture with empty grid returns 1024x1024 image")
    func renderTextureSize() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        let img = vm.renderGridTexture()
        #expect(img.size.width == 1024)
        #expect(img.size.height == 1024)
    }

    @Test("renderGridTexture with a colored cell returns non-nil image")
    func renderTextureWithCell() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.gridState[0][0] = -50
        let img = vm.renderGridTexture()
        #expect(img.cgImage != nil)
    }

    // MARK: - Distance gating

    @Test("distanceExceeded returns true when position moved beyond gate")
    func distanceBeyondGate() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        // Set last recorded position manually
        vm.setLastPosition(SIMD3<Float>(0, 0, 0))
        #expect(vm.distanceExceeded(from: SIMD3<Float>(0.5, 0, 0)) == true)
    }

    @Test("distanceExceeded returns false when position is close")
    func distanceWithinGate() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        vm.setLastPosition(SIMD3<Float>(0, 0, 0))
        #expect(vm.distanceExceeded(from: SIMD3<Float>(0.1, 0, 0)) == false)
    }

    @Test("distanceExceeded returns true when no last position (first point)")
    func distanceFirstPoint() {
        let vm = ARContinuousHeatmapViewModel(session: ARContinuousHeatmapSession())
        #expect(vm.distanceExceeded(from: SIMD3<Float>(0, 0, 0)) == true)
    }
}
