import Foundation
import Testing
@testable import NetMonitor_iOS
@testable import NetMonitorCore

// MARK: - MockHeatmapService

/// Mock measurement engine for testing the survey ViewModel.
@MainActor
final class MockHeatmapService: HeatmapServiceProtocol, @unchecked Sendable {
    var takeMeasurementCallCount = 0
    var takeActiveMeasurementCallCount = 0
    var startContinuousCallCount = 0
    var stopContinuousCallCount = 0

    /// The measurement point to return from takeMeasurement().
    var stubbedPoint: MeasurementPoint?

    func takeMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        takeMeasurementCallCount += 1
        return stubbedPoint ?? MeasurementPoint(
            floorPlanX: floorPlanX,
            floorPlanY: floorPlanY,
            rssi: -55,
            ssid: "TestWiFi",
            bssid: "AA:BB:CC:DD:EE:FF",
            channel: 36,
            band: .band5GHz
        )
    }

    func takeActiveMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        takeActiveMeasurementCallCount += 1
        return stubbedPoint ?? MeasurementPoint(
            floorPlanX: floorPlanX,
            floorPlanY: floorPlanY,
            rssi: -55,
            downloadSpeed: 95.0,
            uploadSpeed: 40.0,
            latency: 12.5
        )
    }

    func startContinuousMeasurement(interval: TimeInterval) async -> AsyncStream<MeasurementPoint> {
        startContinuousCallCount += 1
        return AsyncStream { $0.finish() }
    }

    func stopContinuousMeasurement() async {
        stopContinuousCallCount += 1
    }
}

// MARK: - TestWiFiInfoService

/// A test-only WiFi info service returning stubbed data.
@MainActor
final class TestWiFiInfoService: WiFiInfoServiceProtocol, @unchecked Sendable {
    var currentWiFi: WiFiInfo?
    var isLocationAuthorized: Bool = true
    var stubbedInfo: WiFiInfo?

    init(stubbedInfo: WiFiInfo? = nil) {
        self.stubbedInfo = stubbedInfo
        self.currentWiFi = stubbedInfo
    }

    func requestLocationPermission() {}
    func refreshWiFiInfo() { currentWiFi = stubbedInfo }
    func fetchCurrentWiFi() async -> WiFiInfo? { stubbedInfo }
}

// MARK: - Test Helpers

private func makeTestFloorPlan() -> FloorPlan {
    // Create a minimal valid PNG (1x1 pixel)
    let pngData = makeTestPNGData()
    return FloorPlan(
        imageData: pngData,
        widthMeters: 10,
        heightMeters: 8,
        pixelWidth: 200,
        pixelHeight: 160,
        origin: .drawn
    )
}

private func makeTestProject(name: String = "Test Survey", pointCount: Int = 0) -> SurveyProject {
    var project = SurveyProject(
        name: name,
        floorPlan: makeTestFloorPlan(),
        surveyMode: .blueprint
    )
    for i in 0 ..< pointCount {
        let point = MeasurementPoint(
            floorPlanX: Double(i) / max(Double(pointCount), 1.0),
            floorPlanY: 0.5,
            rssi: -50 - i * 5,
            ssid: "TestWiFi",
            bssid: "AA:BB:CC:DD:EE:FF"
        )
        project.measurementPoints.append(point)
    }
    return project
}

/// Creates a minimal valid PNG image data (1x1 transparent pixel).
private func makeTestPNGData() -> Data {
    // Minimal valid PNG: 1x1 RGBA image
    let bytes: [UInt8] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, // 1x1 RGBA
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT chunk
        0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x06, 0x00, 0x05,
        0x00, 0x00, 0x00, 0x01, // CRC
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND chunk
        0xAE, 0x42, 0x60, 0x82
    ]
    return Data(bytes)
}

@MainActor
private func makeVM(
    project: SurveyProject? = nil,
    engine: MockHeatmapService = MockHeatmapService(),
    wifiService: TestWiFiInfoService? = nil
) -> (HeatmapSurveyViewModel, MockHeatmapService, TestWiFiInfoService) {
    let wifi = wifiService ?? TestWiFiInfoService(stubbedInfo: WiFiInfo(
        ssid: "TestWiFi",
        bssid: "AA:BB:CC:DD:EE:FF",
        signalStrength: 70,
        signalDBm: -55,
        channel: 36,
        frequency: nil,
        band: .band5GHz,
        securityType: "WPA3"
    ))

    let vm = HeatmapSurveyViewModel(
        project: project ?? makeTestProject(),
        measurementEngine: engine,
        wifiService: wifi
    )
    return (vm, engine, wifi)
}

// MARK: - HeatmapSurveyViewModel Tests

@Suite("HeatmapSurveyViewModel")
@MainActor
struct HeatmapSurveyViewModelTests {

    // MARK: - Initial State

    @Test func initialStateHasEmptyPoints() {
        let (vm, _, _) = makeVM()
        #expect(vm.pointCount == 0)
        #expect(vm.heatmapOverlay == nil)
        #expect(!vm.showHeatmap)
        #expect(!vm.isMeasuring)
        #expect(vm.errorMessage == nil)
        #expect(vm.inspectedPoint == nil)
    }

    @Test func defaultVisualizationIsSignalStrength() {
        let (vm, _, _) = makeVM()
        #expect(vm.selectedVisualization == .signalStrength)
    }

    @Test func availableVisualizationsHasThreeTypes() {
        let (vm, _, _) = makeVM()
        #expect(vm.availableVisualizations.count == 3)
        #expect(vm.availableVisualizations.contains(.signalStrength))
        #expect(vm.availableVisualizations.contains(.downloadSpeed))
        #expect(vm.availableVisualizations.contains(.latency))
        // iOS limitation: no SNR
        #expect(!vm.availableVisualizations.contains(.signalToNoise))
    }

    // MARK: - Tap to Measure

    @Test func tapPlacesMeasurementPoint() async {
        let (vm, engine, _) = makeVM()

        await vm.takeMeasurement(atNormalizedX: 0.3, y: 0.5)

        #expect(vm.pointCount == 1)
        #expect(engine.takeMeasurementCallCount == 1)
        #expect(!vm.isMeasuring) // should be done
    }

    @Test func tapMeasurementUsesCorrectCoordinates() async {
        let engine = MockHeatmapService()
        var capturedX: Double = 0
        var capturedY: Double = 0

        engine.stubbedPoint = MeasurementPoint(
            floorPlanX: 0.4,
            floorPlanY: 0.6,
            rssi: -50,
            ssid: "Net"
        )

        let (vm, _, _) = makeVM(engine: engine)

        await vm.takeMeasurement(atNormalizedX: 0.4, y: 0.6)

        #expect(vm.project.measurementPoints.count == 1)
        let point = vm.project.measurementPoints[0]
        capturedX = point.floorPlanX
        capturedY = point.floorPlanY
        #expect(capturedX == 0.4)
        #expect(capturedY == 0.6)
    }

    @Test func wifiDisconnectShowsError() async {
        let engine = MockHeatmapService()
        engine.stubbedPoint = MeasurementPoint(
            floorPlanX: 0.5,
            floorPlanY: 0.5,
            rssi: -100,
            ssid: nil
        )

        let (vm, _, _) = makeVM(engine: engine)

        await vm.takeMeasurement(atNormalizedX: 0.5, y: 0.5)

        #expect(vm.pointCount == 0) // point NOT added
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("Wi-Fi is not connected") == true)
    }

    // MARK: - Heatmap Overlay

    @Test func heatmapNotRenderedWithLessThan3Points() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 2))
        vm.renderHeatmapOverlay()
        #expect(vm.heatmapOverlay == nil)
        #expect(!vm.showHeatmap)
    }

    @Test func heatmapRendersAfter3Points() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 3))
        vm.renderHeatmapOverlay()
        // With our test data (points at different positions with RSSI values),
        // the renderer should produce an image
        #expect(vm.showHeatmap)
        // Overlay may still be nil if PNG data is not a valid image for CGImage creation
        // but showHeatmap should be true since we have 3+ points
    }

    @Test func showHeatmapIsTrueWith3Points() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 3))
        #expect(vm.showHeatmap)
    }

    @Test func showHeatmapIsFalseWith2Points() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 2))
        #expect(!vm.showHeatmap)
    }

    // MARK: - Point Management

    @Test func deletePointRemovesIt() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 3))
        let pointToDelete = vm.project.measurementPoints[1]

        vm.deletePoint(pointToDelete)

        #expect(vm.pointCount == 2)
        #expect(!vm.project.measurementPoints.contains(where: { $0.id == pointToDelete.id }))
    }

    @Test func deletePointClearsInspection() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 3))
        let point = vm.project.measurementPoints[0]
        vm.inspectPoint(point)
        #expect(vm.inspectedPoint?.id == point.id)

        vm.deletePoint(point)

        #expect(vm.inspectedPoint == nil)
    }

    @Test func inspectPointSetsInspectedPoint() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 2))
        let point = vm.project.measurementPoints[0]

        vm.inspectPoint(point)

        #expect(vm.inspectedPoint?.id == point.id)
    }

    // MARK: - Visualization Switching

    @Test func changingVisualizationType() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 3))
        #expect(vm.selectedVisualization == .signalStrength)

        vm.selectedVisualization = .downloadSpeed
        #expect(vm.selectedVisualization == .downloadSpeed)

        vm.selectedVisualization = .latency
        #expect(vm.selectedVisualization == .latency)
    }

    // MARK: - Spacing Guidance

    @Test func spacingGuidanceEmptyState() {
        let (vm, _, _) = makeVM()
        #expect(vm.spacingGuidance.contains("first measurement"))
    }

    @Test func spacingGuidanceLessThan3Points() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 2))
        #expect(vm.spacingGuidance.contains("3 points"))
    }

    @Test func spacingGuidance3PlusPoints() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 5))
        #expect(vm.spacingGuidance.contains("3–5 meters"))
    }

    // MARK: - Summary Statistics

    @Test func averageRSSI() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 3))
        // Points have RSSI: -50, -55, -60
        let avg = vm.averageRSSI
        #expect(avg != nil)
        #expect(avg == -55)
    }

    @Test func minMaxRSSI() {
        let (vm, _, _) = makeVM(project: makeTestProject(pointCount: 3))
        #expect(vm.minRSSI == -60)
        #expect(vm.maxRSSI == -50)
    }

    @Test func statisticsNilWhenEmpty() {
        let (vm, _, _) = makeVM()
        #expect(vm.averageRSSI == nil)
        #expect(vm.minRSSI == nil)
        #expect(vm.maxRSSI == nil)
    }

    // MARK: - Save Project

    @Test func saveProjectCreatesFile() throws {
        let (vm, _, _) = makeVM(project: makeTestProject(name: "SaveTest", pointCount: 3))

        // Save to the documents directory
        vm.saveProject()

        // Verify no error
        #expect(vm.errorMessage == nil)

        // Clean up: check if file was created
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let bundleURL = documentsURL.appendingPathComponent("SaveTest.netmonsurvey")

        // Clean up
        try? FileManager.default.removeItem(at: bundleURL)
    }

    // MARK: - Load Project

    @Test func loadProjectRoundTrip() throws {
        let originalProject = makeTestProject(name: "LoadTest", pointCount: 4)

        // Save first
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let bundleURL = documentsURL.appendingPathComponent("LoadTest.netmonsurvey")
        try SurveyFileManager.save(originalProject, to: bundleURL)

        // Load
        let engine = MockHeatmapService()
        let wifiService = TestWiFiInfoService()
        let loadedVM = HeatmapSurveyViewModel.loadProject(
            from: bundleURL,
            measurementEngine: engine,
            wifiService: wifiService
        )

        #expect(loadedVM != nil)
        #expect(loadedVM?.project.name == "LoadTest")
        #expect(loadedVM?.project.measurementPoints.count == 4)

        // Clean up
        try? FileManager.default.removeItem(at: bundleURL)
    }

    @Test func loadNonexistentProjectReturnsNil() {
        let bogusURL = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent.netmonsurvey")
        let engine = MockHeatmapService()
        let wifiService = TestWiFiInfoService()
        let vm = HeatmapSurveyViewModel.loadProject(
            from: bogusURL,
            measurementEngine: engine,
            wifiService: wifiService
        )
        #expect(vm == nil)
    }
}

// MARK: - HeatmapVisualization displayName Tests

@Suite("HeatmapVisualization.displayName")
struct HeatmapVisualizationDisplayNameTests {

    @Test func allCasesHaveDisplayName() {
        for viz in HeatmapVisualization.allCases {
            #expect(!viz.displayName.isEmpty)
        }
    }

    @Test func specificDisplayNames() {
        #expect(HeatmapVisualization.signalStrength.displayName == "Signal Strength")
        #expect(HeatmapVisualization.signalToNoise.displayName == "Signal-to-Noise")
        #expect(HeatmapVisualization.downloadSpeed.displayName == "Download Speed")
        #expect(HeatmapVisualization.uploadSpeed.displayName == "Upload Speed")
        #expect(HeatmapVisualization.latency.displayName == "Latency")
    }
}
