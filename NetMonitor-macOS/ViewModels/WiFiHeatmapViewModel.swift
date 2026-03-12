import AppKit
import Foundation
import NetMonitorCore
import SwiftUI

// MARK: - WiFiHeatmapViewModel

@MainActor
@Observable
final class WiFiHeatmapViewModel {

    // MARK: - Survey State

    var surveyProject: SurveyProject?
    var measurementPoints: [MeasurementPoint] = []
    var isSurveying: Bool = false
    var isMeasuring: Bool = false
    var pendingMeasurementLocation: CGPoint?

    // MARK: - Live Signal

    private(set) var currentSignal: WiFiHeatmapService.SignalSnapshot?
    private(set) var nearbyAPs: [NearbyAP] = []

    // MARK: - Sidebar State

    enum SidebarMode: String, CaseIterable {
        case survey
        case analyze
    }

    var sidebarMode: SidebarMode = .survey
    var isSidebarCollapsed: Bool = false

    // MARK: - Visualization

    var selectedVisualization: HeatmapVisualization = .signalStrength
    var colorScheme: HeatmapColorScheme = .thermal
    var overlayOpacity: Double = 0.7
    var coverageThreshold: Double = -70 // dBm
    var isCoverageThresholdEnabled: Bool = false

    // MARK: - AP Filter

    var selectedAPFilter: String? // BSSID to filter by, nil = all

    var uniqueBSSIDs: [(bssid: String, ssid: String)] {
        let seen = Dictionary(grouping: measurementPoints, by: { $0.bssid ?? "unknown" })
        return seen.compactMap { (bssid, points) in
            guard bssid != "unknown" else { return nil }
            let ssid = points.first?.ssid ?? bssid
            return (bssid: bssid, ssid: ssid)
        }.sorted { $0.ssid < $1.ssid }
    }

    // MARK: - Measurement Mode

    enum MeasurementMode: String, CaseIterable {
        case passive
        case active
    }

    var measurementMode: MeasurementMode = .passive

    // MARK: - Calibration

    var isCalibrating: Bool = false
    var isCalibrated: Bool = false
    var calibrationPoints: [CalibrationPoint] = []
    var showCalibrationSheet: Bool = false

    // MARK: - Canvas

    var heatmapCGImage: CGImage?
    var showImportSheet: Bool = false
    var showPhotoPicker: Bool = false

    // MARK: - Heatmap State

    var isHeatmapGenerated: Bool = false

    // MARK: - Services

    private let heatmapService = WiFiHeatmapService()
    private var wifiEngine: WiFiMeasurementEngine?
    private var signalPollTask: Task<Void, Never>?
    private let renderer: HeatmapRenderer

    // MARK: - Undo

    private var undoStack: [[MeasurementPoint]] = []

    // MARK: - Init

    init() {
        renderer = HeatmapRenderer()
        setupEngine()
    }

    private func setupEngine() {
        let wifiService = MacWiFiInfoService()
        let speedService = SpeedTestService()
        let pingService = PingService()
        wifiEngine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedService,
            pingService: pingService
        )
    }

    // MARK: - Lifecycle

    func onAppear() {
        startSignalPolling()
    }

    func onDisappear() {
        stopSignalPolling()
    }

    // MARK: - Signal Polling

    func startSignalPolling() {
        guard signalPollTask == nil else { return }
        signalPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.currentSignal = self.heatmapService.currentSignal()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopSignalPolling() {
        signalPollTask?.cancel()
        signalPollTask = nil
    }

    // MARK: - Nearby AP Scan

    func refreshNearbyAPs() {
        nearbyAPs = heatmapService.scanForNearbyAPs()
    }

    // MARK: - Survey Control

    func startSurvey() {
        guard surveyProject != nil, isCalibrated else { return }
        isSurveying = true
        sidebarMode = .survey
        isHeatmapGenerated = false
        heatmapCGImage = nil
    }

    func stopSurvey() {
        isSurveying = false
        generateHeatmap()
    }

    // MARK: - Measurement

    func takeMeasurement(at normalizedPoint: CGPoint) async {
        guard surveyProject != nil, !isMeasuring else { return }
        isMeasuring = true
        pendingMeasurementLocation = normalizedPoint
        defer {
            isMeasuring = false
            pendingMeasurementLocation = nil
        }

        saveUndoState()

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

    // MARK: - Heatmap Generation

    func generateHeatmap() {
        let filteredPoints: [MeasurementPoint]
        if let bssid = selectedAPFilter {
            filteredPoints = measurementPoints.filter { $0.bssid == bssid }
        } else {
            filteredPoints = measurementPoints
        }

        guard !filteredPoints.isEmpty else {
            heatmapCGImage = nil
            isHeatmapGenerated = false
            return
        }

        let config = HeatmapRenderer.Configuration(
            opacity: overlayOpacity
        )
        let localRenderer = HeatmapRenderer(configuration: config)

        Task.detached { [selectedVisualization, colorScheme] in
            let image = localRenderer.render(
                points: filteredPoints,
                visualization: selectedVisualization,
                colorScheme: colorScheme
            )
            await MainActor.run { [weak self] in
                self?.heatmapCGImage = image
                self?.isHeatmapGenerated = true
            }
        }
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
            widthMeters: 10.0,
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
        heatmapCGImage = nil
        isHeatmapGenerated = false

        // Mandatory calibration after import
        startCalibration()
    }

    func importFloorPlan(imageData: Data, name: String) throws {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw HeatmapError.invalidImage
        }

        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: 10.0,
            heightMeters: 10.0,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            origin: .imported
        )

        surveyProject = SurveyProject(
            name: name,
            floorPlan: floorPlan
        )
        measurementPoints = []
        heatmapCGImage = nil
        isHeatmapGenerated = false

        startCalibration()
    }

    // MARK: - Calibration

    func startCalibration() {
        isCalibrating = true
        isCalibrated = false
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

        project.floorPlan = FloorPlan(
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

        surveyProject = project
        isCalibrating = false
        isCalibrated = true
        calibrationPoints = []
        showCalibrationSheet = false
    }

    // MARK: - Undo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        measurementPoints = previous
        if isHeatmapGenerated { generateHeatmap() }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    private func saveUndoState() {
        undoStack.append(measurementPoints)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    // MARK: - Point Management

    func deletePoint(id: UUID) {
        saveUndoState()
        measurementPoints.removeAll { $0.id == id }
        if isHeatmapGenerated { generateHeatmap() }
    }

    func clearMeasurements() {
        saveUndoState()
        measurementPoints = []
        heatmapCGImage = nil
        isHeatmapGenerated = false
    }

    // MARK: - Project Save/Load

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
        isCalibrated = surveyProject?.floorPlan.calibrationPoints?.isEmpty == false
        if !measurementPoints.isEmpty {
            generateHeatmap()
        }
    }

    // MARK: - Export

    func exportPNG(canvasSize: CGSize) -> Data? {
        guard let heatmapCGImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: heatmapCGImage)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Computed

    var filteredPoints: [MeasurementPoint] {
        if let bssid = selectedAPFilter {
            return measurementPoints.filter { $0.bssid == bssid }
        }
        return measurementPoints
    }

    var averageRSSI: Double? {
        let pts = filteredPoints
        guard !pts.isEmpty else { return nil }
        return Double(pts.reduce(0) { $0 + $1.rssi }) / Double(pts.count)
    }

    var minRSSI: Int? { filteredPoints.map(\.rssi).min() }
    var maxRSSI: Int? { filteredPoints.map(\.rssi).max() }
}

// MARK: - HeatmapError

enum HeatmapError: Error, LocalizedError {
    case invalidImage
    case noFloorPlan
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Invalid image format"
        case .noFloorPlan: "No floor plan loaded"
        case .saveFailed: "Failed to save project"
        }
    }
}
