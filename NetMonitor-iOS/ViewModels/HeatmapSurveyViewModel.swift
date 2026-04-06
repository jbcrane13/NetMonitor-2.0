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

// MARK: - SavedSurveyInfo

struct SavedSurveyInfo: Identifiable {
    let name: String
    let url: URL
    let modifiedDate: Date
    let fileSize: Int

    var id: URL { url }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
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

    // MARK: - Live RSSI Polling

    private var signalPollTask: Task<Void, Never>?
    /// Adaptive polling interval — increases when Shortcuts round-trip exceeds 1.5s.
    private var pollInterval: TimeInterval = 2.0

    // MARK: - Dependencies

    private let renderer: HeatmapRenderer
    private let projectManager: ProjectSaveLoadManager
    private var heatmapService: IOSHeatmapService?

    // MARK: - Init

    init() {
        renderer = HeatmapRenderer()
        projectManager = ProjectSaveLoadManager()
    }

    /// Inject the heatmap service after construction (services require DI from the app).
    func configure(service: IOSHeatmapService) {
        self.heatmapService = service
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
        startSignalPolling()
        if isContinuousScan {
            startContinuousScanTimer()
        }
    }

    func stopSurvey() {
        isSurveying = false
        stopSignalPolling()
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

    // MARK: - Live RSSI Polling

    private func startSignalPolling() {
        signalPollTask?.cancel()
        signalPollTask = Task<Void, Never> { [weak self] in
            while !Task.isCancelled {
                guard let self, let service = self.heatmapService else {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                let start = ContinuousClock.now
                let point = await service.takeMeasurement(at: 0, floorPlanY: 0)
                let elapsed = ContinuousClock.now - start

                if Task.isCancelled { return }

                self.currentRSSI = point.rssi
                self.currentSSID = point.ssid

                // Adaptive backoff: if round-trip exceeds 1.5s, slow down polling
                let roundTripSeconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e18
                if roundTripSeconds > 1.5 {
                    self.pollInterval = min(self.pollInterval + 0.5, 5.0)
                } else {
                    self.pollInterval = max(2.0, self.pollInterval - 0.2)
                }

                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    private func stopSignalPolling() {
        signalPollTask?.cancel()
        signalPollTask = nil
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
        if let service = heatmapService {
            if measurementMode == .active {
                point = await service.takeActiveMeasurement(
                    at: Double(normalizedPoint.x),
                    floorPlanY: Double(normalizedPoint.y)
                )
            } else {
                point = await service.takeMeasurement(
                    at: Double(normalizedPoint.x),
                    floorPlanY: Double(normalizedPoint.y)
                )
            }
        } else {
            // Fallback without service — use current polled values
            point = MeasurementPoint(
                floorPlanX: normalizedPoint.x,
                floorPlanY: normalizedPoint.y,
                rssi: currentRSSI,
                ssid: currentSSID
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

    func autoSave() {
        guard let project = surveyProject else { return }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let saveURL = documentsURL?.appendingPathComponent("\(project.name).netmonsurvey") else { return }
        do {
            try saveProject(to: saveURL)
        } catch {
            errorMessage = "Auto-save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Saved Projects

    /// Lists all .netmonsurvey files in the Documents directory.
    static func listSavedProjects() -> [SavedSurveyInfo] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let documentsURL else { return [] }

        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "netmonsurvey" }
            .compactMap { url -> SavedSurveyInfo? in
                let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let name = url.deletingPathExtension().lastPathComponent
                return SavedSurveyInfo(
                    name: name,
                    url: url,
                    modifiedDate: attrs?.contentModificationDate ?? Date.distantPast,
                    fileSize: attrs?.fileSize ?? 0
                )
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }

    /// Deletes a saved project file.
    static func deleteSavedProject(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
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

            // Draw measurement dots with glow
            for point in filteredPoints {
                let x = point.floorPlanX * canvasSize.width
                let y = point.floorPlanY * canvasSize.height
                let color = rssiColor(point.rssi)
                let dotRadius: CGFloat = 6

                // Outer glow
                let glowRect = CGRect(
                    x: x - dotRadius * 1.5,
                    y: y - dotRadius * 1.5,
                    width: dotRadius * 3,
                    height: dotRadius * 3
                )
                ctx.cgContext.setFillColor(color.withAlphaComponent(0.3).cgColor)
                ctx.cgContext.fillEllipse(in: glowRect)

                // Inner dot
                let dotRect = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                ctx.cgContext.setFillColor(color.withAlphaComponent(0.8).cgColor)
                ctx.cgContext.fillEllipse(in: dotRect)

                // Center highlight
                let highlightRect = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                ctx.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.6).cgColor)
                ctx.cgContext.fillEllipse(in: highlightRect)
            }

            _ = project
        }
    }

    /// Exports the project as a .netmonsurvey file URL for sharing.
    func exportProjectFile() -> URL? {
        guard var project = surveyProject else { return nil }
        project.measurementPoints = measurementPoints

        let fileName = project.name
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).netmonsurvey")

        do {
            try projectManager.save(project: project, to: tempURL)
            return tempURL
        } catch {
            return nil
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
