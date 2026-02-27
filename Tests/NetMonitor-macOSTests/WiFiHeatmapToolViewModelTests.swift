import Testing
import Foundation
@testable import NetMonitor_macOS
import NetMonitorCore

// MARK: - Mock WiFiHeatmapService

/// A controllable mock that records calls and returns predetermined data.
final class MockWiFiHeatmapService: WiFiHeatmapServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()

    // Tracking
    var startSurveyCallCount = 0
    var stopSurveyCallCount = 0
    var recordedPoints: [(signalStrength: Int, x: Double, y: Double)] = []

    // Internal storage
    private var _dataPoints: [HeatmapDataPoint] = []

    func startSurvey() {
        lock.withLock {
            startSurveyCallCount += 1
            _dataPoints = []
            recordedPoints = []
        }
    }

    func stopSurvey() {
        lock.withLock {
            stopSurveyCallCount += 1
        }
    }

    func recordDataPoint(signalStrength: Int, x: Double, y: Double) {
        let pt = HeatmapDataPoint(x: x, y: y, signalStrength: signalStrength, timestamp: Date())
        lock.withLock {
            _dataPoints.append(pt)
            recordedPoints.append((signalStrength, x, y))
        }
    }

    func getSurveyData() -> [HeatmapDataPoint] {
        lock.withLock { _dataPoints }
    }
}

// MARK: - UserDefaults cleanup key

/// The ViewModel uses this key internally for persistence.
private let surveysKey = "wifiHeatmap_surveys_mac"

// MARK: - Tests

@Suite("WiFiHeatmapToolViewModel")
@MainActor
struct WiFiHeatmapToolViewModelTests {

    // Clean up UserDefaults before and after each test to avoid cross-contamination.
    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: surveysKey)
    }

    // MARK: - Initial State

    @Test func initialStateDefaults() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        #expect(vm.isSurveying == false)
        #expect(vm.surveys.isEmpty)
        #expect(vm.selectedSurveyID == nil)
        #expect(vm.colorScheme == .thermal)
        #expect(vm.displayOverlays.contains(.gradient))
        #expect(vm.currentRSSI == 0)
        #expect(vm.calibration == nil)
        #expect(vm.preferredUnit == .feet)
        #expect(vm.floorplanImage == nil)
        #expect(vm.zoomScale == 1.0)
        #expect(vm.panOffset == .zero)

        cleanDefaults()
    }

    // MARK: - Start Survey

    @Test func startSurveySetsState() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.startSurvey()

        #expect(vm.isSurveying == true)
        #expect(mock.startSurveyCallCount == 1)
        #expect(vm.statusMessage.contains("Click the canvas"))

        // Calling startSurvey again while already surveying should be a no-op
        vm.startSurvey()
        #expect(mock.startSurveyCallCount == 1)  // guard prevented re-entry, count unchanged

        // Cleanup
        vm.stopSurvey()
        cleanDefaults()
    }

    // MARK: - Stop Survey

    @Test func stopSurveyWithDataCreatesSurvey() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.startSurvey()

        // Simulate recording data via the mock directly (service side)
        mock.recordDataPoint(signalStrength: -50, x: 0.5, y: 0.5)
        mock.recordDataPoint(signalStrength: -60, x: 0.8, y: 0.3)

        vm.stopSurvey()

        #expect(vm.isSurveying == false)
        #expect(mock.stopSurveyCallCount == 1)
        #expect(vm.surveys.count == 1)
        #expect(vm.surveys.first?.dataPoints.count == 2)
        #expect(vm.selectedSurveyID == vm.surveys.first?.id)
        #expect(vm.statusMessage.contains("2 measurements"))

        cleanDefaults()
    }

    @Test func stopSurveyWithNoDataDoesNotCreateSurvey() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.startSurvey()
        vm.stopSurvey()

        #expect(vm.isSurveying == false)
        #expect(vm.surveys.isEmpty)
        #expect(vm.statusMessage.contains("No data recorded"))

        cleanDefaults()
    }

    @Test func stopSurveyWhenNotSurveyingIsNoOp() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.stopSurvey()

        #expect(vm.isSurveying == false)
        #expect(mock.stopSurveyCallCount == 0)

        cleanDefaults()
    }

    // MARK: - Record Data Point

    @Test func recordDataPointNormalizesCoordinates() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.startSurvey()

        // Set currentRSSI so the VM uses a known value
        // The VM reads currentRSSI from its own property; since mock is not WiFiHeatmapService,
        // macService will be nil. currentRSSI defaults to 0, so the fallback path in recordDataPoint
        // will use simulatedRSSI() or random. We need to ensure currentRSSI is set.
        // Looking at the code: rssi = currentRSSI != 0 ? currentRSSI : ...
        // Since currentRSSI starts at 0 and the signalRefreshTask sets it from macService?.currentRSSI()
        // which will be nil (mock isn't WiFiHeatmapService), it'll use macService?.simulatedRSSI()
        // which is also nil, so it'll use Int.random.
        // For the test, we record the point and then inspect what the mock received.

        let canvasSize = CGSize(width: 400, height: 200)
        let point = CGPoint(x: 200, y: 100)

        vm.recordDataPoint(at: point, in: canvasSize)

        #expect(mock.recordedPoints.count == 1)
        let recorded = mock.recordedPoints[0]
        #expect(recorded.x == 0.5, "x should be 200/400 = 0.5")
        #expect(recorded.y == 0.5, "y should be 100/200 = 0.5")
        // Signal strength is random here, just verify it's in valid range
        #expect(recorded.signalStrength <= -45)
        #expect(recorded.signalStrength >= -80)

        // Data points should be populated after recording
        #expect(vm.dataPoints.count == 1)

        vm.stopSurvey()
        cleanDefaults()
    }

    @Test func recordDataPointWhenNotSurveyingIsNoOp() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.recordDataPoint(at: CGPoint(x: 100, y: 100), in: CGSize(width: 400, height: 400))

        #expect(mock.recordedPoints.isEmpty)

        cleanDefaults()
    }

    @Test func recordDataPointWithZeroSizeIsNoOp() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.startSurvey()
        vm.recordDataPoint(at: CGPoint(x: 100, y: 100), in: CGSize(width: 0, height: 400))
        #expect(mock.recordedPoints.isEmpty)

        vm.recordDataPoint(at: CGPoint(x: 100, y: 100), in: CGSize(width: 400, height: 0))
        #expect(mock.recordedPoints.isEmpty)

        vm.stopSurvey()
        cleanDefaults()
    }

    @Test func recordDataPointAtCorners() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.startSurvey()

        let canvasSize = CGSize(width: 800, height: 600)

        // Top-left corner
        vm.recordDataPoint(at: CGPoint(x: 0, y: 0), in: canvasSize)
        // Bottom-right corner
        vm.recordDataPoint(at: CGPoint(x: 800, y: 600), in: canvasSize)

        #expect(mock.recordedPoints.count == 2)
        #expect(mock.recordedPoints[0].x == 0.0)
        #expect(mock.recordedPoints[0].y == 0.0)
        #expect(mock.recordedPoints[1].x == 1.0)
        #expect(mock.recordedPoints[1].y == 1.0)

        vm.stopSurvey()
        cleanDefaults()
    }

    // MARK: - Select Survey

    @Test func selectSurveyUpdatesState() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        // Create two surveys
        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -55, x: 0.1, y: 0.2)
        vm.stopSurvey()

        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -70, x: 0.9, y: 0.8)
        mock.recordDataPoint(signalStrength: -65, x: 0.5, y: 0.5)
        vm.stopSurvey()

        #expect(vm.surveys.count == 2)

        // Surveys are inserted at index 0, so the second survey is first
        let firstSurvey = vm.surveys[1]  // the first survey created (pushed down)
        vm.selectSurvey(firstSurvey)

        #expect(vm.selectedSurveyID == firstSurvey.id)
        #expect(vm.dataPoints.count == 1)
        #expect(vm.dataPoints[0].signalStrength == -55)

        cleanDefaults()
    }

    // MARK: - Delete Survey

    @Test func deleteSurveyRemovesFromArray() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        // Create a survey
        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -50, x: 0.5, y: 0.5)
        vm.stopSurvey()

        #expect(vm.surveys.count == 1)

        let survey = vm.surveys[0]
        vm.deleteSurvey(survey)

        #expect(vm.surveys.isEmpty)

        cleanDefaults()
    }

    @Test func deleteSelectedSurveyUpdatesSelection() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        // Create two surveys
        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -55, x: 0.1, y: 0.2)
        vm.stopSurvey()

        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -70, x: 0.9, y: 0.8)
        vm.stopSurvey()

        #expect(vm.surveys.count == 2)

        // Delete the selected (most recent, at index 0)
        let selected = vm.surveys[0]
        #expect(vm.selectedSurveyID == selected.id)
        vm.deleteSurvey(selected)

        // Selection should move to the remaining survey (now first)
        #expect(vm.surveys.count == 1)
        #expect(vm.selectedSurveyID == vm.surveys.first?.id)

        cleanDefaults()
    }

    @Test func deleteAllSurveysClearsSelection() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -50, x: 0.5, y: 0.5)
        vm.stopSurvey()

        let survey = vm.surveys[0]
        vm.deleteSurvey(survey)

        #expect(vm.surveys.isEmpty)
        #expect(vm.selectedSurveyID == nil)

        cleanDefaults()
    }

    // MARK: - Calibration

    @Test func setCalibrationStoresCorrectValues() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.setCalibration(pixelDist: 200.0, realDist: 10.0, unit: .feet)

        #expect(vm.calibration != nil)
        #expect(vm.calibration?.pixelDistance == 200.0)
        #expect(vm.calibration?.realDistance == 10.0)
        #expect(vm.calibration?.unit == .feet)

        cleanDefaults()
    }

    @Test func setCalibrationWithMeters() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.setCalibration(pixelDist: 150.0, realDist: 5.0, unit: .meters)

        #expect(vm.calibration?.unit == .meters)
        #expect(vm.calibration?.pixelsPerUnit == 30.0)

        cleanDefaults()
    }

    @Test func clearCalibrationSetsNil() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.setCalibration(pixelDist: 200.0, realDist: 10.0, unit: .feet)
        #expect(vm.calibration != nil)

        vm.clearCalibration()
        #expect(vm.calibration == nil)

        cleanDefaults()
    }

    @Test func calibrationPersistedWithSurvey() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.setCalibration(pixelDist: 300.0, realDist: 15.0, unit: .meters)
        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -55, x: 0.5, y: 0.5)
        vm.stopSurvey()

        #expect(vm.surveys.count == 1)
        let survey = vm.surveys[0]
        #expect(survey.calibration?.pixelDistance == 300.0)
        #expect(survey.calibration?.realDistance == 15.0)
        #expect(survey.calibration?.unit == .meters)

        cleanDefaults()
    }

    // MARK: - Persistence Round-Trip

    @Test func persistenceRoundTripPreservesData() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm1 = WiFiHeatmapToolViewModel(service: mock)

        // Create a survey with calibration
        vm1.setCalibration(pixelDist: 100.0, realDist: 5.0, unit: .feet)
        vm1.startSurvey()
        mock.recordDataPoint(signalStrength: -45, x: 0.25, y: 0.75)
        mock.recordDataPoint(signalStrength: -60, x: 0.50, y: 0.50)
        vm1.stopSurvey()

        #expect(vm1.surveys.count == 1)
        let originalSurvey = vm1.surveys[0]

        // Create a second ViewModel that loads from UserDefaults
        let mock2 = MockWiFiHeatmapService()
        let vm2 = WiFiHeatmapToolViewModel(service: mock2)

        #expect(vm2.surveys.count == 1, "Surveys should be loaded from UserDefaults")
        let loadedSurvey = vm2.surveys[0]

        #expect(loadedSurvey.id == originalSurvey.id)
        #expect(loadedSurvey.name == originalSurvey.name)
        #expect(loadedSurvey.mode == originalSurvey.mode)
        #expect(loadedSurvey.dataPoints.count == originalSurvey.dataPoints.count)

        // Verify data points preserved
        #expect(loadedSurvey.dataPoints[0].x == 0.25)
        #expect(loadedSurvey.dataPoints[0].y == 0.75)
        #expect(loadedSurvey.dataPoints[0].signalStrength == -45)
        #expect(loadedSurvey.dataPoints[1].x == 0.50)
        #expect(loadedSurvey.dataPoints[1].y == 0.50)
        #expect(loadedSurvey.dataPoints[1].signalStrength == -60)

        // Verify calibration preserved
        #expect(loadedSurvey.calibration?.pixelDistance == 100.0)
        #expect(loadedSurvey.calibration?.realDistance == 5.0)
        #expect(loadedSurvey.calibration?.unit == .feet)

        // Verify selectedSurveyID is restored
        #expect(vm2.selectedSurveyID == loadedSurvey.id)

        // Verify dataPoints are loaded from first survey
        #expect(vm2.dataPoints.count == 2)

        cleanDefaults()
    }

    @Test func persistenceAfterDelete() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm1 = WiFiHeatmapToolViewModel(service: mock)

        // Create two surveys
        vm1.startSurvey()
        mock.recordDataPoint(signalStrength: -50, x: 0.1, y: 0.1)
        vm1.stopSurvey()

        vm1.startSurvey()
        mock.recordDataPoint(signalStrength: -60, x: 0.2, y: 0.2)
        vm1.stopSurvey()

        #expect(vm1.surveys.count == 2)

        // Delete first in the array (most recent)
        vm1.deleteSurvey(vm1.surveys[0])
        #expect(vm1.surveys.count == 1)

        // Reload and verify only one survey persisted
        let mock2 = MockWiFiHeatmapService()
        let vm2 = WiFiHeatmapToolViewModel(service: mock2)

        #expect(vm2.surveys.count == 1)

        cleanDefaults()
    }

    // MARK: - Color Scheme

    @Test func colorSchemeChangeUpdatesProperty() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        #expect(vm.colorScheme == .thermal)

        vm.colorScheme = .signal
        #expect(vm.colorScheme == .signal)

        vm.colorScheme = .nebula
        #expect(vm.colorScheme == .nebula)

        vm.colorScheme = .arctic
        #expect(vm.colorScheme == .arctic)

        cleanDefaults()
    }

    // MARK: - Display Overlays

    @Test func displayOverlaysDefaultContainsGradient() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        #expect(vm.displayOverlays.contains(.gradient))

        cleanDefaults()
    }

    @Test func displayOverlaysCanAddMultiple() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.displayOverlays.insert(.dots)
        #expect(vm.displayOverlays.contains(.gradient))
        #expect(vm.displayOverlays.contains(.dots))

        vm.displayOverlays.insert(.contour)
        #expect(vm.displayOverlays.contains(.contour))

        vm.displayOverlays.insert(.deadZones)
        #expect(vm.displayOverlays.contains(.deadZones))

        cleanDefaults()
    }

    @Test func displayOverlaysCanRemove() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.displayOverlays.insert(.dots)
        #expect(vm.displayOverlays.contains(.dots))

        vm.displayOverlays.remove(.dots)
        #expect(!vm.displayOverlays.contains(.dots))

        // Gradient should still be there
        #expect(vm.displayOverlays.contains(.gradient))

        // Can remove gradient too
        vm.displayOverlays.remove(.gradient)
        #expect(!vm.displayOverlays.contains(.gradient))

        cleanDefaults()
    }

    // MARK: - Preferred Unit

    @Test func preferredUnitDefaultIsFeet() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        #expect(vm.preferredUnit == .feet)

        cleanDefaults()
    }

    @Test func preferredUnitCanBeChanged() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.preferredUnit = .meters
        #expect(vm.preferredUnit == .meters)

        vm.preferredUnit = .feet
        #expect(vm.preferredUnit == .feet)

        cleanDefaults()
    }

    // MARK: - Survey Mode

    @Test func surveyModeIsFreeformWithoutFloorplan() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        #expect(vm.floorplanImage == nil)

        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -50, x: 0.5, y: 0.5)
        vm.stopSurvey()

        #expect(vm.surveys.first?.mode == .freeform)

        cleanDefaults()
    }

    // MARK: - Survey Naming

    @Test func surveysAreNamedSequentially() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -50, x: 0.1, y: 0.1)
        vm.stopSurvey()

        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -55, x: 0.2, y: 0.2)
        vm.stopSurvey()

        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -60, x: 0.3, y: 0.3)
        vm.stopSurvey()

        // Surveys are inserted at index 0, so newest is first
        #expect(vm.surveys[0].name == "Survey 3")
        #expect(vm.surveys[1].name == "Survey 2")
        #expect(vm.surveys[2].name == "Survey 1")

        cleanDefaults()
    }

    // MARK: - Multiple Surveys Workflow

    @Test func multipleSurveysAccumulate() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        for i in 1...5 {
            vm.startSurvey()
            mock.recordDataPoint(signalStrength: -40 - i * 5, x: Double(i) / 10.0, y: Double(i) / 10.0)
            vm.stopSurvey()
        }

        #expect(vm.surveys.count == 5)
        // Most recent is at index 0
        #expect(vm.selectedSurveyID == vm.surveys[0].id)

        cleanDefaults()
    }

    // MARK: - Status Messages

    @Test func statusMessageOnStart() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        #expect(vm.statusMessage == "Click 'Start Survey' to begin")

        vm.startSurvey()
        #expect(vm.statusMessage == "Click the canvas to record signal at each location")

        vm.stopSurvey()
        cleanDefaults()
    }

    @Test func statusMessageOnRecordDataPoint() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        vm.startSurvey()
        vm.recordDataPoint(at: CGPoint(x: 200, y: 100), in: CGSize(width: 400, height: 200))

        // Status message should contain "dBm" and coordinates
        #expect(vm.statusMessage.contains("dBm"))
        #expect(vm.statusMessage.contains("0.50"))

        vm.stopSurvey()
        cleanDefaults()
    }

    // MARK: - Select Survey Restores Calibration

    @Test func selectSurveyRestoresCalibration() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        // Survey 1 with calibration
        vm.setCalibration(pixelDist: 100.0, realDist: 5.0, unit: .feet)
        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -50, x: 0.5, y: 0.5)
        vm.stopSurvey()

        // Survey 2 without calibration
        vm.clearCalibration()
        vm.startSurvey()
        mock.recordDataPoint(signalStrength: -60, x: 0.3, y: 0.3)
        vm.stopSurvey()

        // Now selected is Survey 2 (no calibration)
        #expect(vm.calibration == nil)

        // Select Survey 1 to restore its calibration
        let survey1 = vm.surveys[1]  // older survey is at index 1
        vm.selectSurvey(survey1)

        #expect(vm.calibration?.pixelDistance == 100.0)
        #expect(vm.calibration?.realDistance == 5.0)
        #expect(vm.calibration?.unit == .feet)

        cleanDefaults()
    }

    // MARK: - Zoom and Pan

    @Test func zoomAndPanDefaults() {
        cleanDefaults()
        let mock = MockWiFiHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: mock)

        #expect(vm.zoomScale == 1.0)
        #expect(vm.panOffset == .zero)

        vm.zoomScale = 2.5
        #expect(vm.zoomScale == 2.5)

        vm.panOffset = CGSize(width: 100, height: -50)
        #expect(vm.panOffset.width == 100)
        #expect(vm.panOffset.height == -50)

        cleanDefaults()
    }
}
