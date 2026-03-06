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

    // MARK: - Calibration State
    var isCalibrating: Bool = false
    var calibrationPoints: [CalibrationPoint] = []
    var calibrationDistance: Double = 5.0 // meters
    var showCalibrationSheet: Bool = false

    // MARK: - Services
    private var wifiEngine: WiFiMeasurementEngine?
    private var renderer: HeatmapRenderer
    private let wifiService = MacWiFiInfoService()
    private var rssiTimer: Timer?

    // MARK: - Measurement Mode
    enum MeasurementMode: String, CaseIterable {
        case passive  // RSSI, SNR only
        case active   // + speed test, latency
    }

    init() {
        renderer = HeatmapRenderer()
        setupEngine()
    }

    // MARK: - Live RSSI Updates

    func startLiveRSSITimer() {
        guard rssiTimer == nil else { return }
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.updateLiveRSSI()
            }
        }
    }

    func stopLiveRSSITimer() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    func onAppear() {
        startLiveRSSITimer()
    }

    func onDisappear() {
        stopLiveRSSITimer()
    }

    private func updateLiveRSSI() async {
        let wifiInfo = await wifiService.fetchCurrentWiFi()
        currentRSSI = wifiInfo?.signalDBm ?? -100
        currentSSID = wifiInfo?.ssid
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

    private func setupEngine() {
        let speedService = SpeedTestService()
        let pingService = PingService()
        wifiEngine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedService,
            pingService: pingService
        )
    }

    // MARK: - Floor Plan Import

    func importFloorPlan(from url: URL) throws {
        let imageData = try Data(contentsOf: url)
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw HeatmapError.invalidImage
        }

        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: 10.0,  // Default, user can calibrate
            heightMeters: 10.0,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            origin: .imported
        )

        surveyProject = SurveyProject(
            name: url.deletingPathExtension().lastPathComponent,
            floorPlan: floorPlan
        )
        measurementPoints = []
    }

    // MARK: - Measurement

    func takeMeasurement(at normalizedPoint: CGPoint) async {
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

        measurementPoints.append(point)
    }

    // MARK: - Heatmap Rendering

    func renderHeatmap() -> CGImage? {
        renderer.render(points: measurementPoints, visualization: selectedVisualization)
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

    // MARK: - Clear

    func clearMeasurements() {
        measurementPoints = []
    }
}

// MARK: - Errors

enum HeatmapError: Error, LocalizedError {
    case invalidImage
    case noFloorPlan
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Invalid image format"
        case .noFloorPlan: return "No floor plan loaded"
        case .saveFailed: return "Failed to save project"
        }
    }
}
