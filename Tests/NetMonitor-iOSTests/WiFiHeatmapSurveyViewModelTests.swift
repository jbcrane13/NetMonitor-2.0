import Testing
import Foundation
import CoreGraphics
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - Mock Service

private final class MockWiFiHeatmapService: WiFiHeatmapServiceProtocol, @unchecked Sendable {
    var startCallCount = 0
    var stopCallCount = 0
    var recordCallCount = 0
    private var _data: [HeatmapDataPoint] = []

    func startSurvey() {
        startCallCount += 1
        _data = []
    }

    func stopSurvey() {
        stopCallCount += 1
    }

    func recordDataPoint(signalStrength: Int, x: Double, y: Double) {
        recordCallCount += 1
        _data.append(HeatmapDataPoint(x: x, y: y, signalStrength: signalStrength))
    }

    func getSurveyData() -> [HeatmapDataPoint] { _data }
}

// MARK: - Tests

@Suite("WiFiHeatmapSurveyViewModel")
@MainActor
struct WiFiHeatmapSurveyViewModelTests {

    @Test func initialStateIsNotSurveying() {
        let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        #expect(vm.isSurveying == false)
    }

    @Test func initialDataPointsAreEmpty() {
        let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        #expect(vm.dataPoints.isEmpty)
    }

    @Test func initialModeIsFreeform() {
        let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        #expect(vm.selectedMode == .freeform)
    }

    @Test func startSurveySetsIsSurveyingTrue() {
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapSurveyViewModel(service: mock)
        vm.startSurvey()
        #expect(vm.isSurveying == true)
    }

    @Test func startSurveyCallsService() {
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapSurveyViewModel(service: mock)
        vm.startSurvey()
        #expect(mock.startCallCount == 1)
    }

    @Test func stopSurveySetsIsSurveyingFalse() {
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapSurveyViewModel(service: mock)
        vm.startSurvey()
        vm.stopSurvey()
        #expect(vm.isSurveying == false)
    }

    @Test func stopSurveyCallsService() {
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapSurveyViewModel(service: mock)
        vm.startSurvey()
        vm.stopSurvey()
        #expect(mock.stopCallCount == 1)
    }

    @Test func recordDataPointCallsService() {
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapSurveyViewModel(service: mock)
        vm.startSurvey()
        vm.recordDataPoint(at: CGPoint(x: 100, y: 200), in: CGSize(width: 400, height: 800))
        #expect(mock.recordCallCount == 1)
    }

    @Test func recordDataPointNormalizesCoordinates() {
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapSurveyViewModel(service: mock)
        vm.startSurvey()
        vm.recordDataPoint(at: CGPoint(x: 100, y: 200), in: CGSize(width: 400, height: 800))
        let data = mock.getSurveyData()
        #expect(data.count == 1)
        #expect(abs(data[0].x - 0.25) < 0.001)
        #expect(abs(data[0].y - 0.25) < 0.001)
    }

    @Test func recordDataPointIgnoredWhenNotSurveying() {
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapSurveyViewModel(service: mock)
        vm.recordDataPoint(at: CGPoint(x: 100, y: 200), in: CGSize(width: 400, height: 800))
        #expect(mock.recordCallCount == 0)
    }

    @Test func stopSurveySavesSurveyWhenDataExists() {
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapSurveyViewModel(service: mock)
        vm.startSurvey()
        vm.recordDataPoint(at: CGPoint(x: 50, y: 50), in: CGSize(width: 100, height: 100))
        let countBefore = vm.surveys.count
        vm.stopSurvey()
        #expect(vm.surveys.count == countBefore + 1)
    }

    @Test func deleteSurveyRemovesFromList() {
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapSurveyViewModel(service: mock)
        vm.startSurvey()
        vm.recordDataPoint(at: CGPoint(x: 50, y: 50), in: CGSize(width: 100, height: 100))
        vm.stopSurvey()
        guard let survey = vm.surveys.first else { return }
        let countBefore = vm.surveys.count
        vm.deleteSurvey(survey)
        #expect(vm.surveys.count == countBefore - 1)
    }

    @Test func signalTextIsDoubleDashWhenNotSurveying() {
        let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        #expect(vm.signalText == "--")
    }

    @Test func signalTextShowsDbmWhenSurveying() {
        let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        vm.startSurvey()
        #expect(vm.signalText.contains("dBm"))
    }

    @Test func startSurveyTwiceDoesNotDoubleStart() {
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapSurveyViewModel(service: mock)
        vm.startSurvey()
        vm.startSurvey()
        #expect(mock.startCallCount == 1)
    }

    // MARK: - Calibration tests

    @Test("setCalibration stores scale on viewModel")
    @MainActor
    func setCalibrationStores() {
        let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        vm.setCalibration(pixelDist: 100, realDist: 10, unit: .feet)
        #expect(vm.calibration?.pixelsPerUnit == 10.0)
        #expect(vm.calibration?.unit == .feet)
    }

    @Test("clearCalibration removes scale")
    @MainActor
    func clearCalibration() {
        let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        vm.setCalibration(pixelDist: 100, realDist: 10, unit: .feet)
        vm.clearCalibration()
        #expect(vm.calibration == nil)
    }

    @Test("default colorScheme is thermal")
    @MainActor
    func defaultColorScheme() {
        let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        #expect(vm.colorScheme == .thermal)
    }

    @Test("default preferredUnit is feet")
    @MainActor
    func defaultUnit() {
        let vm = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        #expect(vm.preferredUnit == .feet)
    }

    @Test("surveys persist through UserDefaults round-trip")
    @MainActor
    func surveysPersistThroughReload() {
        // Clear before AND after to prevent interference from prior test runs
        UserDefaults.standard.removeObject(forKey: "wifiHeatmap_surveys")
        defer { UserDefaults.standard.removeObject(forKey: "wifiHeatmap_surveys") }
        let vm1 = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        vm1.startSurvey()
        vm1.recordDataPoint(at: CGPoint(x: 100, y: 100), in: CGSize(width: 400, height: 400))
        vm1.stopSurvey()
        #expect(vm1.surveys.count == 1)
        let vm2 = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        #expect(vm2.surveys.count >= 1, "Fresh VM should load the persisted survey")
    }

    @Test("colorScheme change persists to UserDefaults")
    @MainActor
    func colorSchemePersisted() {
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.Keys.heatmapColorScheme) }
        let vm1 = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        vm1.colorScheme = .arctic
        let vm2 = WiFiHeatmapSurveyViewModel(service: MockWiFiHeatmapService())
        #expect(vm2.colorScheme == .arctic, "colorScheme should survive a fresh VM init")
    }
}
