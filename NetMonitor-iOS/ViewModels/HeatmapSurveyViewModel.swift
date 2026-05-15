import CoreGraphics
import Foundation
import NetMonitorCore
import UIKit

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

// MARK: - HeatmapSurveyViewModel

/// iOS heatmap survey state management.
///
/// Uses ``IOSHeatmapService`` for Shortcuts-based Wi-Fi measurement and
/// ``HeatmapRenderer`` for IDW interpolation + color mapping.
@MainActor
@Observable
final class HeatmapSurveyViewModel {

    // MARK: - MeasurementMode

    enum MeasurementMode: String, CaseIterable {
        case passive    // Wi-Fi signal only (~1-2s)
        case active     // Signal + speed test + ping (~8-10s)
    }

    // MARK: - Survey State

    var surveyProject: SurveyProject?
    var measurementPoints: [MeasurementPoint] = []
    var isSurveying: Bool = false
    var errorMessage: String?

    // MARK: - Measurement

    var measurementMode: MeasurementMode = .passive
    var isMeasuring: Bool = false
    var pendingMeasurementLocation: CGPoint?
    var currentRSSI: Int = -100
    var currentSSID: String?

    // MARK: - Visualization

    var selectedVisualization: HeatmapVisualization = .signalStrength
    var selectedColorScheme: HeatmapColorScheme = .thermal
    var heatmapOpacity: Double = 0.7
    var heatmapImage: CGImage?
    var isHeatmapGenerated: Bool = false

    // MARK: - Calibration

    var isCalibrating: Bool = false
    var isCalibrated: Bool = false
    var calibrationPoints: [CalibrationPoint] = []
    var calibrationDistance: Double = 5.0
    var showCalibrationSheet: Bool = false

    // MARK: - Floor Plan

    var showImportSheet: Bool = false
    var showPhotoPicker: Bool = false
    var floorPlanImage: UIImage?

    // MARK: - Canvas

    var canvasScale: CGFloat = 1.0
    var canvasOffset: CGSize = .zero

    // MARK: - AP Filter

    var selectedAPFilter: String?

    var uniqueBSSIDs: [(bssid: String, ssid: String)] {
        let seen = Dictionary(grouping: measurementPoints, by: { $0.bssid ?? "unknown" })
        return seen.compactMap { bssid, points in
            guard bssid != "unknown" else { return nil }
            let ssid = points.first?.ssid ?? bssid
            return (bssid: bssid, ssid: ssid)
        }.sorted { $0.ssid < $1.ssid }
    }

    // MARK: - Continuous Scan

    var isContinuousScan: Bool = false
    var continuousScanInterval: Double = 3.0
    private var continuousScanTask: Task<Void, Never>?

    // MARK: - Undo

    private var undoStack: [[MeasurementPoint]] = []
    var canUndo: Bool { !undoStack.isEmpty }

    // MARK: - Persistence

    var isSaving: Bool = false
    var lastSaveDate: Date?
    private var measurementsSinceLastSave: Int = 0

    // MARK: - Dependencies

    private let renderer: HeatmapRenderer
    private let fileManager: HeatmapFileManager
    private let exporter: HeatmapExporter
    private let heatmapService: any HeatmapServiceProtocol

    // MARK: - Init

    init(
        service: any HeatmapServiceProtocol,
        fileManager: HeatmapFileManager = HeatmapFileManager(),
        exporter: HeatmapExporter = HeatmapExporter()
    ) {
        self.heatmapService = service
        self.fileManager = fileManager
        self.exporter = exporter
        renderer = HeatmapRenderer()
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

    var hasFloorPlan: Bool { surveyProject != nil }

    // MARK: - Floor Plan Import

    func importFloorPlan(imageData: Data, name: String) throws {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
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
        floorPlanImage = uiImage
        measurementPoints = []
        calibrationPoints = []
        heatmapImage = nil
        isHeatmapGenerated = false
        undoStack = []

        startCalibration()
    }

    func importFloorPlan(imageData: Data, width: Int, height: Int) {
        measurementPoints = []
        calibrationPoints = []
        heatmapImage = nil
        isHeatmapGenerated = false
        undoStack = []

        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: Double(width) * 0.01,
            heightMeters: Double(height) * 0.01,
            pixelWidth: width,
            pixelHeight: height,
            origin: .imported
        )

        surveyProject = SurveyProject(
            name: "Untitled Survey",
            floorPlan: floorPlan
        )
    }

    func importFloorPlan(from url: URL) throws {
        let imageData = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        try importFloorPlan(imageData: imageData, name: name)
    }

    // MARK: - Blueprint Import

    func importBlueprint(from url: URL) throws {
        let manager = BlueprintSaveLoadManager()
        let blueprint = try manager.load(from: url)
        importBlueprintProject(blueprint)
    }

    /// Import a RoomPlan-scanned blueprint directly as a pre-calibrated floor plan.
    func importBlueprintProject(_ blueprint: BlueprintProject) {
        guard let floor = blueprint.floors.first else {
            errorMessage = HeatmapError.noFloorPlan.localizedDescription
            return
        }

        let floorPlan = BlueprintSaveLoadManager.floorPlanFromBlueprint(floor)

        surveyProject = SurveyProject(
            name: blueprint.name,
            floorPlan: floorPlan,
            metadata: SurveyMetadata(
                buildingName: blueprint.metadata.buildingName,
                floorNumber: floor.label,
                notes: blueprint.metadata.notes
            )
        )
        floorPlanImage = UIImage(data: floorPlan.imageData)
        measurementPoints = []
        heatmapImage = nil
        isHeatmapGenerated = false
        undoStack = []

        // Blueprint is pre-calibrated from RoomPlan dimensions
        isCalibrating = false
        isCalibrated = true
        calibrationPoints = []
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

    func skipCalibration() {
        isCalibrating = false
        isCalibrated = true
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

    func completeCalibration(distance: Double, isFeet: Bool) {
        let realDistance = isFeet ? distance * 0.3048 : distance
        completeCalibration(withDistance: realDistance)
    }

    func completeCalibration(withDistance distanceMeters: Double) {
        guard calibrationPoints.count == 2 else {
            calibrationPoints = []
            isCalibrating = false
            return
        }

        guard var project = surveyProject else {
            calibrationPoints = []
            isCalibrating = false
            return
        }

        let metersPerPixel = CalibrationPoint.metersPerPixel(
            pointA: calibrationPoints[0],
            pointB: calibrationPoints[1],
            knownDistanceMeters: distanceMeters
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

    // MARK: - Survey Control

    func startSurvey() {
        guard surveyProject != nil, isCalibrated else { return }
        isSurveying = true
        isHeatmapGenerated = false
        heatmapImage = nil
        // Note: live RSSI polling via service.takeMeasurement is intentionally
        // disabled on iOS — each call opens the Shortcuts companion, which
        // steals focus every poll interval and makes the app unusable. The
        // current-signal indicator updates after each explicit user-initiated
        // measurement instead.
        if isContinuousScan {
            startContinuousScanTimer()
        }
    }

    func stopSurvey() {
        isSurveying = false
        stopContinuousScanTimer()
        updateHeatmap()
    }

    private func startContinuousScanTimer() {
        continuousScanTask?.cancel()
        continuousScanTask = Task<Void, Never> { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.continuousScanInterval))
                if Task.isCancelled { return }
                guard self.isSurveying, let loc = self.pendingMeasurementLocation else { continue }
                await self.takeMeasurement(at: loc)
            }
        }
    }

    private func stopContinuousScanTimer() {
        continuousScanTask?.cancel()
        continuousScanTask = nil
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
            point = await heatmapService.takeActiveMeasurement(
                at: Double(normalizedPoint.x),
                floorPlanY: Double(normalizedPoint.y)
            )
        } else {
            point = await heatmapService.takeMeasurement(
                at: Double(normalizedPoint.x),
                floorPlanY: Double(normalizedPoint.y)
            )
        }

        measurementPoints.append(point)
        measurementsSinceLastSave += 1

        // Update live display
        currentRSSI = point.rssi
        currentSSID = point.ssid

        // Auto-update heatmap after 3+ points
        if measurementPoints.count >= 3 {
            updateHeatmap()
        }

        // Auto-save every 5 measurements
        if measurementsSinceLastSave >= 5 {
            autoSave()
        }
    }

    // MARK: - Point Management

    func deleteMeasurement(id: UUID) {
        saveUndoState()
        measurementPoints.removeAll { $0.id == id }
        if isHeatmapGenerated { updateHeatmap() }
    }

    func clearMeasurements() {
        saveUndoState()
        measurementPoints = []
        heatmapImage = nil
        isHeatmapGenerated = false
    }

    // MARK: - Undo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        measurementPoints = previous
        if isHeatmapGenerated { updateHeatmap() }
    }

    private func saveUndoState() {
        undoStack.append(measurementPoints)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    // MARK: - Heatmap Generation

    func updateHeatmap() {
        let pointsToRender: [MeasurementPoint]
        if let bssid = selectedAPFilter {
            pointsToRender = measurementPoints.filter { $0.bssid == bssid }
        } else {
            pointsToRender = measurementPoints
        }

        guard !pointsToRender.isEmpty else {
            heatmapImage = nil
            isHeatmapGenerated = false
            return
        }

        let config = HeatmapRenderer.Configuration(opacity: heatmapOpacity)
        let localRenderer = HeatmapRenderer(configuration: config)

        Task.detached { [selectedVisualization, selectedColorScheme] in
            let image = localRenderer.render(
                points: pointsToRender,
                visualization: selectedVisualization,
                colorScheme: selectedColorScheme
            )
            await MainActor.run { [weak self] in
                self?.heatmapImage = image
                self?.isHeatmapGenerated = true
            }
        }
    }

    // MARK: - Project Save/Load

    func saveProject(to url: URL) throws {
        guard var project = surveyProject else { return }
        isSaving = true
        defer { isSaving = false }

        project.measurementPoints = measurementPoints
        try fileManager.save(project: project, to: url)
        lastSaveDate = Date()
        measurementsSinceLastSave = 0
    }

    func loadProject(from url: URL) throws {
        let project = try fileManager.load(from: url)

        surveyProject = project
        measurementPoints = project.measurementPoints
        isCalibrated = project.floorPlan.calibrationPoints?.isEmpty == false
        floorPlanImage = UIImage(data: project.floorPlan.imageData)
        undoStack = []
        if !measurementPoints.isEmpty {
            updateHeatmap()
        }
    }

    func autoSave() {
        guard let project = surveyProject,
              let saveURL = fileManager.autoSaveURL(for: project.name)
        else { return }
        do {
            try saveProject(to: saveURL)
        } catch {
            errorMessage = "Auto-save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    func exportImage(canvasSize: CGSize) -> UIImage? {
        guard surveyProject != nil else { return nil }
        return exporter.renderImage(
            floorPlanImage: floorPlanImage,
            heatmapImage: heatmapImage,
            points: filteredPoints,
            heatmapOpacity: heatmapOpacity,
            canvasSize: canvasSize
        )
    }

    /// Exports the project as a .netmonsurvey file URL for sharing.
    func exportProjectFile() -> URL? {
        guard var project = surveyProject else { return nil }
        project.measurementPoints = measurementPoints
        return exporter.exportProjectFile(project: project, fileManager: fileManager)
    }

    /// Compatibility wrapper for existing call sites and tests.
    func qualityLabel(_ rssi: Int) -> String {
        RSSIQuality(rssi: rssi).label
    }

}
