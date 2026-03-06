import Foundation
import SwiftUI
import NetMonitorCore

@MainActor
@Observable
final class HeatmapSurveyViewModel {
    // MARK: - Published State
    var surveyProject: SurveyProject?
    var measurementPoints: [MeasurementPoint] = []
    var selectedVisualization: HeatmapVisualization = .signalStrength
    var measurementMode: MeasurementMode = .passive
    var isMeasuring: Bool = false
    var showImportSheet: Bool = false
    var currentRSSI: Int = -100
    var currentSSID: String?
    var isLocationAuthorized: Bool = false
    var wifiStatusMessage: String? = nil

    // MARK: - Calibration State
    var isCalibrating: Bool = false
    var calibrationPoints: [CalibrationPoint] = []
    var calibrationDistance: Double = 5.0 // meters
    var showCalibrationSheet: Bool = false

    // MARK: - Services
    private var wifiEngine: WiFiMeasurementEngine?
    private var renderer: HeatmapRenderer
    private var wifiService: WiFiInfoService?
    private var rssiTimer: Timer?

    // MARK: - Measurement Mode
    enum MeasurementMode: String, CaseIterable {
        case passive
        case active
    }

    init() {
        renderer = HeatmapRenderer()
    }

    private func setupEngineIfNeeded() {
        if wifiEngine == nil {
            let service = WiFiInfoService()
            self.wifiService = service
            let speedService = SpeedTestService()
            let pingService = PingService()
            wifiEngine = WiFiMeasurementEngine(
                wifiService: service,
                speedTestService: speedService,
                pingService: pingService
            )
        }
    }

    func onAppear() {
        setupEngineIfNeeded()
        startLiveRSSITimer()
        checkLocationAuthorization()
    }

    func onDisappear() {
        stopLiveRSSITimer()
    }

    // MARK: - Live RSSI Updates (AC-1.4)

    private func startLiveRSSITimer() {
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateLiveRSSI()
            }
        }
    }

    private func stopLiveRSSITimer() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    private func updateLiveRSSI() async {
        guard let service = wifiService else {
            wifiStatusMessage = "WiFi service not initialized"
            print("[HeatmapSurveyViewModel] WiFi service is nil")
            return
        }

        // Re-check location authorization each time
        isLocationAuthorized = service.isLocationAuthorized
        print("[HeatmapSurveyViewModel] Location authorized: \(isLocationAuthorized)")

        if !isLocationAuthorized {
            wifiStatusMessage = "Location permission required"
            print("[HeatmapSurveyViewModel] Location not authorized")
            return
        }

        let wifiInfo = await service.fetchCurrentWiFi()
        print("[HeatmapSurveyViewModel] fetchCurrentWiFi returned: \(wifiInfo != nil ? "success" : "nil")")

        if let wifiInfo {
            currentRSSI = wifiInfo.signalDBm ?? -100
            currentSSID = wifiInfo.ssid
            wifiStatusMessage = nil
            print("[HeatmapSurveyViewModel] Updated RSSI: \(currentRSSI) dBm, SSID: \(wifiInfo.ssid ?? "nil")")
        } else {
            // fetchCurrentWiFi returned nil - could be:
            // 1. Not connected to WiFi
            // 2. NEHotspotNetwork.fetchCurrent() returned nil
            wifiStatusMessage = "No WiFi connection detected"
            print("[HeatmapSurveyViewModel] WiFi info is nil")
        }
    }

    // MARK: - Location Authorization

    func checkLocationAuthorization() {
        guard let service = wifiService else { return }
        isLocationAuthorized = service.isLocationAuthorized
    }

    func requestLocationPermission() {
        wifiService?.requestLocationPermission()
    }

    // MARK: - Floor Plan Import

    func importFloorPlan(imageData: Data, width: Int, height: Int) {
        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: 10.0,
            heightMeters: 10.0,
            pixelWidth: width,
            pixelHeight: height,
            origin: .imported
        )

        surveyProject = SurveyProject(
            name: "Survey",
            floorPlan: floorPlan
        )
        measurementPoints = []
        calibrationPoints = []
    }

    // MARK: - Calibration

    func startCalibration() {
        isCalibrating = true
        calibrationPoints = []
    }

    func cancelCalibration() {
        isCalibrating = false
        calibrationPoints = []
    }

    func addCalibrationPoint(at normalizedPoint: CGPoint) {
        guard calibrationPoints.count < 2 else { return }

        let point = CalibrationPoint(
            pixelX: Double(normalizedPoint.x),
            pixelY: Double(normalizedPoint.y)
        )
        calibrationPoints.append(point)

        if calibrationPoints.count == 2 {
            showCalibrationSheet = true
        }
    }

    func completeCalibration(withDistance distance: Double) {
        guard calibrationPoints.count == 2,
              var project = surveyProject else { return }

        let metersPerPixel = CalibrationPoint.metersPerPixel(
            pointA: calibrationPoints[0],
            pointB: calibrationPoints[1],
            knownDistanceMeters: distance
        )

        let floorPlan = FloorPlan(
            id: project.floorPlan.id,
            imageData: project.floorPlan.imageData,
            widthMeters: Double(project.floorPlan.pixelWidth) * metersPerPixel,
            heightMeters: Double(project.floorPlan.pixelHeight) * metersPerPixel,
            pixelWidth: project.floorPlan.pixelWidth,
            pixelHeight: project.floorPlan.pixelHeight,
            origin: project.floorPlan.origin,
            calibrationPoints: calibrationPoints,
            walls: project.floorPlan.walls
        )

        project.floorPlan = floorPlan
        surveyProject = project
        isCalibrating = false
        calibrationPoints = []
        showCalibrationSheet = false
    }

    // MARK: - Measurement

    func takeMeasurement(at normalizedPoint: CGPoint) async {
        setupEngineIfNeeded()
        guard let project = surveyProject, !isMeasuring else { return }

        isMeasuring = true
        defer { isMeasuring = false }

        let point: MeasurementPoint
        if measurementMode == .active {
            point = await wifiEngine?.takeActiveMeasurement(
                at: normalizedPoint.x,
                floorPlanY: normalizedPoint.y
            ) ?? MeasurementPoint(floorPlanX: normalizedPoint.x, floorPlanY: normalizedPoint.y)
        } else {
            point = await wifiEngine?.takeMeasurement(
                at: normalizedPoint.x,
                floorPlanY: normalizedPoint.y
            ) ?? MeasurementPoint(floorPlanX: normalizedPoint.x, floorPlanY: normalizedPoint.y)
        }

        currentRSSI = point.rssi
        measurementPoints.append(point)
    }

    // MARK: - Heatmap Rendering

    func renderHeatmap() -> CGImage? {
        renderer.render(points: measurementPoints, visualization: selectedVisualization)
    }

    // MARK: - Clear

    func clearMeasurements() {
        measurementPoints = []
    }

    // MARK: - Save/Load

    func saveProject(to url: URL) throws {
        guard var project = surveyProject else { return }
        project.measurementPoints = measurementPoints
        let manager = ProjectSaveLoadManager()
        try manager.save(project: project, to: url)
    }

    func loadProject(from url: URL) throws {
        let manager = ProjectSaveLoadManager()
        surveyProject = try manager.load(from: url)
        measurementPoints = surveyProject?.measurementPoints ?? []
    }
}
