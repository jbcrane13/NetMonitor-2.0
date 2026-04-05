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
/// Modeled after the macOS `WiFiHeatmapViewModel` but adapted for touch/sheet UI
/// and Shortcuts-based Wi-Fi measurement. Phase B (#127) will flesh out remaining
/// implementation including live RSSI polling, IOSHeatmapService integration, and
/// full heatmap rendering pipeline.
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
    private let projectManager: ProjectSaveLoadManager

    // MARK: - Init

    init() {
        renderer = HeatmapRenderer()
        projectManager = ProjectSaveLoadManager()
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

    /// Creates a new survey project from raw image data, decoding to get pixel dimensions.
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

    /// Creates a new survey project from raw image data with explicit pixel dimensions.
    /// Used when pixel dimensions are known without needing to decode the image.
    func importFloorPlan(imageData: Data, width: Int, height: Int) {
        measurementPoints = []
        calibrationPoints = []
        heatmapImage = nil
        isHeatmapGenerated = false
        undoStack = []

        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: Double(width) * 0.01,  // placeholder scale until calibrated
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

        guard let floor = blueprint.floors.first else {
            throw HeatmapError.noFloorPlan
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

        // Blueprint is pre-calibrated
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

    /// Completes calibration using the known real-world distance (in meters) between the two points.
    /// Updates the floor plan's metric dimensions based on the computed scale.
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

    // Phase B (#127) will flesh out remaining implementation:
    // - IOSHeatmapService integration for takeMeasurement
    // - Live RSSI polling
    // - Full heatmap rendering pipeline

    func startSurvey() {
        guard surveyProject != nil, isCalibrated else { return }
        isSurveying = true
        isHeatmapGenerated = false
        heatmapImage = nil
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

        // Create measurement point with current signal data.
        // Phase B (#127): calls IOSHeatmapService for Shortcuts-based signal.
        let point = MeasurementPoint(
            floorPlanX: normalizedPoint.x,
            floorPlanY: normalizedPoint.y,
            rssi: currentRSSI,
            ssid: currentSSID
        )

        measurementPoints.append(point)
        measurementsSinceLastSave += 1

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

        // Use bundle-based manager for .netmonsurvey files, plain JSON otherwise
        if url.pathExtension == "netmonsurvey" {
            try projectManager.save(project: project, to: url)
        } else {
            let data = try JSONEncoder().encode(project)
            try data.write(to: url, options: .atomic)
        }
        lastSaveDate = Date()
        measurementsSinceLastSave = 0
    }

    func loadProject(from url: URL) throws {
        let project: SurveyProject
        if url.pathExtension == "netmonsurvey" {
            project = try projectManager.load(from: url)
        } else {
            let data = try Data(contentsOf: url)
            project = try JSONDecoder().decode(SurveyProject.self, from: data)
        }

        surveyProject = project
        measurementPoints = project.measurementPoints
        isCalibrated = project.floorPlan.calibrationPoints?.isEmpty == false
        floorPlanImage = UIImage(data: project.floorPlan.imageData)
        undoStack = []
        if !measurementPoints.isEmpty {
            updateHeatmap()
        }
    }

    private func autoSave() {
        guard let project = surveyProject else { return }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let saveURL = documentsURL?.appendingPathComponent("\(project.name).netmonsurvey") else { return }
        do {
            try saveProject(to: saveURL)
        } catch {
            // Auto-save failure is non-fatal
            errorMessage = "Auto-save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    func exportImage(canvasSize: CGSize) -> UIImage? {
        guard let project = surveyProject,
              let floorImage = floorPlanImage else { return nil }

        let imageRenderer = UIGraphicsImageRenderer(size: canvasSize)
        return imageRenderer.image { ctx in
            // Draw floor plan
            floorImage.draw(in: CGRect(origin: .zero, size: canvasSize))

            // Draw heatmap overlay
            if let heatmapCG = heatmapImage {
                let heatmapUI = UIImage(cgImage: heatmapCG)
                ctx.cgContext.setAlpha(heatmapOpacity)
                heatmapUI.draw(in: CGRect(origin: .zero, size: canvasSize))
                ctx.cgContext.setAlpha(1.0)
            }

            // Draw measurement dots
            for point in filteredPoints {
                let x = point.floorPlanX * canvasSize.width
                let y = point.floorPlanY * canvasSize.height
                let dotRadius: CGFloat = 6
                let dotRect = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fillEllipse(in: dotRect)
                ctx.cgContext.setStrokeColor(rssiColor(point.rssi).cgColor)
                ctx.cgContext.setLineWidth(2)
                ctx.cgContext.strokeEllipse(in: dotRect)
            }

            _ = project // suppress unused warning
        }
    }

    // MARK: - Helpers

    func rssiColor(_ rssi: Int) -> UIColor {
        switch rssi {
        case -50...0: .systemGreen
        case -60 ..< -50: .systemYellow
        case -70 ..< -60: .systemOrange
        default: .systemRed
        }
    }

    func qualityLabel(_ rssi: Int) -> String {
        switch rssi {
        case -50...0: "Excellent"
        case -60 ..< -50: "Good"
        case -70 ..< -60: "Fair"
        default: "Weak"
        }
    }
}
