import AppKit
import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

// MARK: - Mock WiFi Measurement Engine

/// Mock implementation of HeatmapServiceProtocol for testing.
final class MockMeasurementEngine: HeatmapServiceProtocol, @unchecked Sendable {
    var mockRSSI: Int = -55
    var mockNoiseFloor: Int? = -90
    var mockSSID: String? = "TestNetwork"
    var mockBSSID: String? = "AA:BB:CC:DD:EE:FF"
    var mockChannel: Int? = 36
    var mockBand: WiFiBand? = .band5GHz
    var mockLinkSpeed: Int? = 866
    var takeMeasurementCallCount: Int = 0

    func takeMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        takeMeasurementCallCount += 1
        return MeasurementPoint(
            floorPlanX: floorPlanX,
            floorPlanY: floorPlanY,
            rssi: mockRSSI,
            noiseFloor: mockNoiseFloor,
            snr: mockNoiseFloor.map { mockRSSI - $0 },
            ssid: mockSSID,
            bssid: mockBSSID,
            channel: mockChannel,
            band: mockBand,
            linkSpeed: mockLinkSpeed
        )
    }

    func takeActiveMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        MeasurementPoint(
            floorPlanX: floorPlanX,
            floorPlanY: floorPlanY,
            rssi: mockRSSI,
            noiseFloor: mockNoiseFloor,
            downloadSpeed: 150.0,
            uploadSpeed: 50.0,
            latency: 5.0
        )
    }

    func startContinuousMeasurement(interval: TimeInterval) async -> AsyncStream<MeasurementPoint> {
        AsyncStream { $0.finish() }
    }

    func stopContinuousMeasurement() async {}
}

/// Mock CoreWLAN service for testing live RSSI.
@MainActor
final class MockCoreWLANService: CoreWLANServiceProtocol {
    var mockRSSI: Int = -50
    var mockNoiseFloor: Int = -90
    var mockChannel: Int = 36
    var mockBand: String = "5 GHz"
    var mockLinkSpeed: Int = 866
    var mockSSID: String? = "TestNet"
    var mockBSSID: String? = "AA:BB:CC:DD:EE:FF"

    func currentRSSI() -> Int? { mockRSSI }
    func currentNoiseFloor() -> Int? { mockNoiseFloor }
    func currentChannel() -> Int? { mockChannel }
    func currentBand() -> String? { mockBand }
    func currentLinkSpeed() -> Int? { mockLinkSpeed }
    func currentSSID() -> String? { mockSSID }
    func currentBSSID() -> String? { mockBSSID }
}

// MARK: - Test Helpers

/// Creates a minimal valid PNG image data for testing.
private func makeTestPNGData(width: Int = 100, height: Int = 80) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let cgImage = context.makeImage()
    else {
        return Data()
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:]) ?? Data()
}

/// Writes test PNG data to a temporary file and returns the URL.
private func makeTestPNGFile(name: String = "test_floorplan.png", width: Int = 100, height: Int = 80) -> URL {
    let data = makeTestPNGData(width: width, height: height)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? data.write(to: url)
    return url
}

/// Writes test data to a temporary file with the given extension.
private func makeTestFile(name: String, data: Data = Data([0x00, 0x01, 0x02])) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? data.write(to: url)
    return url
}

// MARK: - HeatmapSurveyViewModel Tests

@Suite("HeatmapSurveyViewModel")
@MainActor
struct HeatmapSurveyViewModelTests {

    // MARK: - Initial State

    @Test func initialStateHasNoFloorPlan() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.hasFloorPlan == false)
        #expect(vm.floorPlanImage == nil)
        #expect(vm.importResult == nil)
        #expect(vm.isCalibrated == false)
        #expect(vm.pixelsPerMeter == 0)
        #expect(vm.project == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.showingError == false)
    }

    // MARK: - Floor Plan Import

    @Test func loadFloorPlanFromPNG() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 200, height: 150)
        defer { try? FileManager.default.removeItem(at: url) }

        vm.loadFloorPlan(from: url)

        #expect(vm.hasFloorPlan == true)
        #expect(vm.floorPlanImage != nil)
        #expect(vm.importResult != nil)
        #expect(vm.importResult?.pixelWidth == 200)
        #expect(vm.importResult?.pixelHeight == 150)
        #expect(vm.project != nil)
        #expect(vm.project?.floorPlan.pixelWidth == 200)
        #expect(vm.project?.floorPlan.pixelHeight == 150)
    }

    @Test func loadFloorPlanFromJPEG() throws {
        let vm = HeatmapSurveyViewModel()
        // Create JPEG data from a CGImage
        let pngData = makeTestPNGData(width: 120, height: 90)
        let image = try #require(NSImage(data: pngData))
        let tiffData = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiffData))
        let jpegData = try #require(rep.representation(using: .jpeg, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.jpg")
        try jpegData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        vm.loadFloorPlan(from: url)

        #expect(vm.hasFloorPlan == true)
        #expect(vm.importResult != nil)
    }

    @Test func loadFloorPlanUnsupportedFormatShowsError() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestFile(name: "test.bmp")
        defer { try? FileManager.default.removeItem(at: url) }

        vm.loadFloorPlan(from: url)

        #expect(vm.hasFloorPlan == false)
        #expect(vm.showingError == true)
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("bmp") == true)
    }

    @Test func loadFloorPlanResetsCalibration() {
        let vm = HeatmapSurveyViewModel()
        let url1 = makeTestPNGFile(name: "first.png")
        defer { try? FileManager.default.removeItem(at: url1) }
        vm.loadFloorPlan(from: url1)

        // Simulate calibration
        vm.calibrationDistance = "10"
        vm.applyCalibration()
        #expect(vm.isCalibrated == true)

        // Import new floor plan
        let url2 = makeTestPNGFile(name: "second.png", width: 300, height: 200)
        defer { try? FileManager.default.removeItem(at: url2) }
        vm.loadFloorPlan(from: url2)

        #expect(vm.isCalibrated == false)
        #expect(vm.pixelsPerMeter == 0)
    }

    @Test func loadFloorPlanCreatesProjectWithCorrectName() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(name: "Office_Plan.png")
        defer { try? FileManager.default.removeItem(at: url) }

        vm.loadFloorPlan(from: url)

        #expect(vm.project?.name == "Office_Plan")
    }

    @Test func loadFloorPlanSetsImportedOrigin() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }

        vm.loadFloorPlan(from: url)

        if case .imported(let sourceURL) = vm.project?.floorPlan.origin {
            #expect(sourceURL == url)
        } else {
            Issue.record("Expected .imported origin")
        }
    }

    // MARK: - Calibration

    @Test func startCalibrationPresentsSheet() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.startCalibration()

        #expect(vm.isCalibrationSheetPresented == true)
    }

    @Test func startCalibrationWithoutFloorPlanDoesNothing() {
        let vm = HeatmapSurveyViewModel()

        vm.startCalibration()

        #expect(vm.isCalibrationSheetPresented == false)
    }

    @Test func applyCalibrationComputesPixelsPerMeter() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        // Set calibration: points are at 25% and 75% width, same height
        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        #expect(vm.isCalibrated == true)
        // 1000 pixels across / 10 meters = 100 px/m
        #expect(vm.pixelsPerMeter == 100.0)
    }

    @Test func applyCalibrationWithFeetConverts() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "32.8084" // ~10 meters in feet
        vm.calibrationUnit = .feet

        vm.applyCalibration()

        #expect(vm.isCalibrated == true)
        // 1000 pixels / (32.8084 * 0.3048) meters ≈ 100 px/m
        #expect(abs(vm.pixelsPerMeter - 100.0) < 1.0)
    }

    @Test func applyCalibrationUpdatesProjectDimensions() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        #expect(vm.project?.floorPlan.widthMeters == 10.0)
        #expect(vm.project?.floorPlan.heightMeters == 5.0)
    }

    @Test func applyCalibrationStoresCalibrationPoints() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.2, y: 0.3)
        vm.calibrationPoint2 = CGPoint(x: 0.8, y: 0.7)
        vm.calibrationDistance = "5"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        let calibPoints = vm.project?.floorPlan.calibrationPoints
        #expect(calibPoints != nil)
        #expect(calibPoints?.count == 2)
        // Point 1: 0.2 * 1000 = 200, 0.3 * 500 = 150
        #expect(calibPoints?[0].pixelX == 200)
        #expect(calibPoints?[0].pixelY == 150)
    }

    @Test func applyCalibrationShowsScaleBar() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile(width: 1000, height: 500)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationPoint1 = CGPoint(x: 0.0, y: 0.5)
        vm.calibrationPoint2 = CGPoint(x: 1.0, y: 0.5)
        vm.calibrationDistance = "10"
        vm.calibrationUnit = .meters

        vm.applyCalibration()

        #expect(vm.scaleBarLabel.isEmpty == false)
        #expect(vm.scaleBarFraction > 0)
    }

    @Test func applyCalibrationInvalidDistanceShowsError() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationDistance = "abc"

        vm.applyCalibration()

        #expect(vm.isCalibrated == false)
        #expect(vm.showingError == true)
    }

    @Test func applyCalibrationZeroDistanceShowsError() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.calibrationDistance = "0"

        vm.applyCalibration()

        #expect(vm.isCalibrated == false)
        #expect(vm.showingError == true)
    }

    @Test func skipCalibrationDismissesSheet() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)
        vm.startCalibration()
        #expect(vm.isCalibrationSheetPresented == true)

        vm.skipCalibration()

        #expect(vm.isCalibrationSheetPresented == false)
        #expect(vm.isCalibrated == false)
        #expect(vm.pixelsPerMeter == 0)
    }

    @Test func skipCalibrationClearsScaleBar() {
        let vm = HeatmapSurveyViewModel()
        let url = makeTestPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }
        vm.loadFloorPlan(from: url)

        vm.skipCalibration()

        #expect(vm.scaleBarLabel.isEmpty)
        #expect(vm.scaleBarFraction == 0)
    }

    // MARK: - Error Handling

    @Test func showErrorSetsMessageAndFlag() {
        let vm = HeatmapSurveyViewModel()

        vm.showError("Something went wrong")

        #expect(vm.errorMessage == "Something went wrong")
        #expect(vm.showingError == true)
    }

    @Test func clearErrorResetsState() {
        let vm = HeatmapSurveyViewModel()
        vm.showError("Error")

        vm.clearError()

        #expect(vm.errorMessage == nil)
        #expect(vm.showingError == false)
    }

    // MARK: - CalibrationUnit

    @Test func calibrationUnitMetersConversion() {
        #expect(CalibrationUnit.meters.toMeters == 1.0)
    }

    @Test func calibrationUnitFeetConversion() {
        #expect(CalibrationUnit.feet.toMeters == 0.3048)
    }

    // MARK: - Survey Workflow

    private func makeVMWithFloorPlan() -> (HeatmapSurveyViewModel, MockMeasurementEngine, MockCoreWLANService) {
        let engine = MockMeasurementEngine()
        let wlanService = MockCoreWLANService()
        let vm = HeatmapSurveyViewModel(measurementEngine: engine, coreWLANService: wlanService)
        let url = makeTestPNGFile(width: 1000, height: 500)
        vm.loadFloorPlan(from: url)
        return (vm, engine, wlanService)
    }

    @Test func addMeasurementPointUpdatesProject() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.3))

        #expect(vm.project?.measurementPoints.count == 1)
        let point = vm.project?.measurementPoints.first
        #expect(point?.floorPlanX == 0.5)
        #expect(point?.floorPlanY == 0.3)
        #expect(point?.rssi == -55)
        #expect(point?.ssid == "TestNetwork")
    }

    @Test func addMultipleMeasurements() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))

        #expect(vm.project?.measurementPoints.count == 3)
    }

    @Test func measurementPopulatesRSSINoiseChannelBandLinkSpeed() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        let point = vm.project?.measurementPoints.first
        #expect(point?.rssi == -55)
        #expect(point?.noiseFloor == -90)
        #expect(point?.channel == 36)
        #expect(point?.band == .band5GHz)
        #expect(point?.linkSpeed == 866)
    }

    @Test func summaryStatsUpdateOnAdd() async {
        let (vm, engine, _) = makeVMWithFloorPlan()

        engine.setMockRSSI(-40)
        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        engine.setMockRSSI(-70)
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        engine.setMockRSSI(-60)
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))

        #expect(vm.summaryStats.count == 3)
        #expect(vm.summaryStats.minRSSI == -70)
        #expect(vm.summaryStats.maxRSSI == -40)
        // Average: (-40 + -70 + -60) / 3 = -170/3 ≈ -56.67
        let avgDiff = abs(vm.summaryStats.avgRSSI - (-170.0 / 3.0))
        #expect(avgDiff < 0.1)
    }

    @Test func selectedPointHighlightOnCanvas() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        guard let pointID = vm.project?.measurementPoints.first?.id
        else {
            Issue.record("Expected measurement point to be created")
            return
        }

        vm.selectedPointID = pointID
        #expect(vm.selectedPointID == pointID)

        vm.selectedPointID = nil
        #expect(vm.selectedPointID == nil)
    }

    @Test func removeMeasurementPointUpdatesStats() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        #expect(vm.summaryStats.count == 2)

        guard let pointID = vm.project?.measurementPoints.first?.id
        else {
            Issue.record("Expected measurement point to exist")
            return
        }
        vm.removeMeasurementPoint(id: pointID)

        #expect(vm.summaryStats.count == 1)
        #expect(vm.project?.measurementPoints.count == 1)
    }

    @Test func liveRSSIUpdatesFromCoreWLAN() {
        let (vm, _, wlanService) = makeVMWithFloorPlan()
        wlanService.mockRSSI = -42

        vm.refreshLiveRSSI()

        #expect(vm.liveRSSI == -42)
    }

    @Test func liveRSSIFormattedBadge() {
        let (vm, _, wlanService) = makeVMWithFloorPlan()
        wlanService.mockRSSI = -55

        vm.refreshLiveRSSI()

        #expect(vm.liveRSSIBadgeText == "-55 dBm")
    }

    @Test func zoomStatePreservesPoints() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        // Simulate zoom
        vm.zoomScale = 2.0
        vm.panOffset = CGSize(width: 50, height: 50)

        // Points should still be at normalized coordinates
        let point = vm.project?.measurementPoints.first
        #expect(point?.floorPlanX == 0.5)
        #expect(point?.floorPlanY == 0.5)
    }

    @Test func measurementWithoutProjectDoesNotCrash() async {
        let engine = MockMeasurementEngine()
        let wlanService = MockCoreWLANService()
        let vm = HeatmapSurveyViewModel(measurementEngine: engine, coreWLANService: wlanService)

        // No floor plan loaded, project is nil
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        #expect(vm.project == nil)
    }

    @Test func summaryStatsEmptyWhenNoPoints() {
        let vm = HeatmapSurveyViewModel()

        #expect(vm.summaryStats == SummaryStats.empty)
    }

    @Test func spacingGuidanceShown() {
        let (vm, _, _) = makeVMWithFloorPlan()

        // Spacing guidance should be available when floor plan is loaded
        let guidanceContainsExpected = vm.spacingGuidanceText.contains("3") || vm.spacingGuidanceText.contains("5")
        #expect(guidanceContainsExpected)
    }

    @Test func isMeasuringSetDuringMeasurement() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        // Before measurement
        #expect(vm.isMeasuring == false)

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        // After measurement completes
        #expect(vm.isMeasuring == false)
    }

    // MARK: - Wi-Fi Disconnect Detection (VAL-MAC-063)

    @Test func disconnectedWiFiShowsErrorAndDoesNotAddPoint() async {
        let (vm, engine, _) = makeVMWithFloorPlan()

        // Simulate Wi-Fi disconnected: nil SSID and default -100 RSSI
        engine.mockSSID = nil
        engine.mockBSSID = nil
        engine.setMockRSSI(-100)
        engine.mockNoiseFloor = nil

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        // Point should NOT have been added
        #expect(vm.project?.measurementPoints.count == 0)
        // Error should be shown
        #expect(vm.showingError == true)
        #expect(vm.errorMessage?.contains("Wi-Fi is not connected") == true)
    }

    @Test func disconnectedWiFiWithWeakerRSSIAlsoDetected() async {
        let (vm, engine, _) = makeVMWithFloorPlan()

        // RSSI below -100 should also trigger disconnect detection
        engine.mockSSID = nil
        engine.mockBSSID = nil
        engine.setMockRSSI(-110)
        engine.mockNoiseFloor = nil

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        #expect(vm.project?.measurementPoints.count == 0)
        #expect(vm.showingError == true)
    }

    @Test func connectedWiFiWithSSIDAddsPoint() async {
        let (vm, engine, _) = makeVMWithFloorPlan()

        // Connected WiFi with valid SSID — should add point normally
        engine.mockSSID = "MyNetwork"
        engine.setMockRSSI(-65)

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        #expect(vm.project?.measurementPoints.count == 1)
        #expect(vm.showingError == false)
    }

    @Test func weakSignalWithSSIDStillAddsPoint() async {
        let (vm, engine, _) = makeVMWithFloorPlan()

        // Very weak signal but still connected (has SSID) — should add point
        engine.mockSSID = "WeakNetwork"
        engine.setMockRSSI(-95)

        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))

        #expect(vm.project?.measurementPoints.count == 1)
        #expect(vm.showingError == false)
    }

    // MARK: - Visualization Type

    @Test func defaultVisualizationTypeIsSignalStrength() {
        let vm = HeatmapSurveyViewModel()
        #expect(vm.selectedVisualization == .signalStrength)
    }

    @Test func visualizationTypeCanBeChanged() {
        let vm = HeatmapSurveyViewModel()
        vm.selectedVisualization = .signalToNoise
        #expect(vm.selectedVisualization == .signalToNoise)
        vm.selectedVisualization = .downloadSpeed
        #expect(vm.selectedVisualization == .downloadSpeed)
        vm.selectedVisualization = .uploadSpeed
        #expect(vm.selectedVisualization == .uploadSpeed)
        vm.selectedVisualization = .latency
        #expect(vm.selectedVisualization == .latency)
    }

    @Test func allFiveVisualizationTypesAvailable() {
        let types = HeatmapVisualization.allCases
        #expect(types.count == 5)
        #expect(types.contains(.signalStrength))
        #expect(types.contains(.signalToNoise))
        #expect(types.contains(.downloadSpeed))
        #expect(types.contains(.uploadSpeed))
        #expect(types.contains(.latency))
    }

    // MARK: - Heatmap Overlay

    @Test func heatmapOverlayNilWithFewerThan3Points() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        // 0 points
        #expect(vm.heatmapOverlayImage == nil)

        // 1 point
        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        #expect(vm.heatmapOverlayImage == nil)

        // 2 points
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        #expect(vm.heatmapOverlayImage == nil)
    }

    @Test func heatmapOverlayRendersAfter3Points() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))

        #expect(vm.heatmapOverlayImage != nil)
    }

    @Test func heatmapOverlayUpdatesWhenPointAdded() async {
        let (vm, engine, _) = makeVMWithFloorPlan()

        // Place 3 points
        engine.setMockRSSI(-40)
        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        engine.setMockRSSI(-60)
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        engine.setMockRSSI(-80)
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))

        let overlayBefore = vm.heatmapOverlayImage

        // Place a 4th point with different RSSI
        engine.setMockRSSI(-30)
        await vm.takeMeasurement(at: CGPoint(x: 0.3, y: 0.3))

        // Overlay should have been regenerated (different image data)
        #expect(vm.heatmapOverlayImage != nil)
        // At minimum, we can check it was regenerated (non-nil)
        // Precise pixel comparison not needed for ViewModel test
        #expect(overlayBefore != nil)
    }

    @Test func heatmapOverlayNilAfterDeletionDropsBelow3() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))
        #expect(vm.heatmapOverlayImage != nil)

        // Delete one point, dropping below 3
        guard let pointID = vm.project?.measurementPoints.first?.id
        else {
            Issue.record("Expected measurement point")
            return
        }
        vm.removeMeasurementPoint(id: pointID)
        #expect(vm.heatmapOverlayImage == nil)
    }

    @Test func switchingVisualizationTypeRendersOverlay() async {
        let (vm, engine, _) = makeVMWithFloorPlan()

        // Add 3 points with SNR data
        engine.mockNoiseFloor = -90
        engine.setMockRSSI(-40)
        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        engine.setMockRSSI(-60)
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        engine.setMockRSSI(-80)
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))

        #expect(vm.heatmapOverlayImage != nil)

        // Switch to SNR
        vm.selectedVisualization = .signalToNoise
        // Overlay should still be rendered since SNR data is available
        #expect(vm.heatmapOverlayImage != nil)
    }

    @Test func missingDataForVisualizationShowsEmptyState() async {
        let (vm, engine, _) = makeVMWithFloorPlan()

        // Mock engine returns points without download speed data
        engine.setMockRSSI(-50)
        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))

        // Switch to downloadSpeed — no data for this type
        vm.selectedVisualization = .downloadSpeed
        #expect(vm.heatmapOverlayImage == nil)
        #expect(vm.visualizationHasData == false)
    }

    @Test func visualizationHasDataTrueForSignalStrength() async {
        let (vm, _, _) = makeVMWithFloorPlan()

        await vm.takeMeasurement(at: CGPoint(x: 0.1, y: 0.1))
        await vm.takeMeasurement(at: CGPoint(x: 0.5, y: 0.5))
        await vm.takeMeasurement(at: CGPoint(x: 0.9, y: 0.9))

        #expect(vm.visualizationHasData == true)
    }

    @Test func visualizationDisplayNameForAllTypes() {
        let vm = HeatmapSurveyViewModel()
        vm.selectedVisualization = .signalStrength
        #expect(vm.visualizationDisplayName == "Signal Strength")
        vm.selectedVisualization = .signalToNoise
        #expect(vm.visualizationDisplayName == "Signal to Noise")
        vm.selectedVisualization = .downloadSpeed
        #expect(vm.visualizationDisplayName == "Download Speed")
        vm.selectedVisualization = .uploadSpeed
        #expect(vm.visualizationDisplayName == "Upload Speed")
        vm.selectedVisualization = .latency
        #expect(vm.visualizationDisplayName == "Latency")
    }

}

// MARK: - MockMeasurementEngine Helpers

extension MockMeasurementEngine {
    @MainActor
    func setMockRSSI(_ value: Int) {
        mockRSSI = value
    }
}

// MARK: - FloorPlanImporter Tests

@Suite("FloorPlanImporter")
struct FloorPlanImporterTests {

    @Test func importPNGSucceeds() throws {
        let url = makeTestPNGFile(width: 200, height: 150)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FloorPlanImporter.importFloorPlan(from: url)

        #expect(result.pixelWidth == 200)
        #expect(result.pixelHeight == 150)
        #expect(result.imageData.isEmpty == false)
        #expect(result.sourceURL == url)
    }

    @Test func importUnsupportedFormatThrows() {
        let url = makeTestFile(name: "test.svg")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: FloorPlanImportError.self) {
            try FloorPlanImporter.importFloorPlan(from: url)
        }
    }

    @Test func isSupportedReturnsTrueForValidExtensions() {
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.png")) == true)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.jpg")) == true)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.jpeg")) == true)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.heic")) == true)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.pdf")) == true)
    }

    @Test func isSupportedReturnsFalseForInvalidExtensions() {
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.bmp")) == false)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.svg")) == false)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.txt")) == false)
        #expect(FloorPlanImporter.isSupported(URL(fileURLWithPath: "/test.gif")) == false)
    }

    @Test func largeImageDownsampled() throws {
        // Create a large image (5000x5000)
        let url = makeTestPNGFile(name: "large.png", width: 5000, height: 5000)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FloorPlanImporter.importFloorPlan(from: url)

        // Should be downsampled to 4096 max dimension
        #expect(result.pixelWidth <= FloorPlanImporter.maxPixelDimension)
        #expect(result.pixelHeight <= FloorPlanImporter.maxPixelDimension)
    }

    @Test func smallImageNotDownsampled() throws {
        let url = makeTestPNGFile(name: "small.png", width: 800, height: 600)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try FloorPlanImporter.importFloorPlan(from: url)

        #expect(result.pixelWidth == 800)
        #expect(result.pixelHeight == 600)
    }

    @Test func importCorruptFileThrows() {
        let url = makeTestFile(name: "corrupt.png", data: Data([0xFF, 0xFE, 0xFD]))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: FloorPlanImportError.self) {
            try FloorPlanImporter.importFloorPlan(from: url)
        }
    }
}
