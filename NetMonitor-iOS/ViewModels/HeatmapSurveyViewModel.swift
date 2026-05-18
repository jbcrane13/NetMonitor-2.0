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
/// Wraps the cross-platform ``HeatmapSurveyState`` (NetMonitorCore) and adds
/// the iOS-specific pieces: ``IOSHeatmapService`` for Shortcuts-based Wi-Fi
/// measurement, ``HeatmapRenderer`` for IDW interpolation + color mapping,
/// ``HeatmapFileManager`` / ``HeatmapExporter`` for persistence + export,
/// continuous-scan timer, UIImage floor-plan rendering, and the
/// `measurementMode` (passive vs active) gating that's specific to the iOS
/// Shortcuts companion latency.
///
/// State that was previously declared and mutated here is now forwarded to
/// `state` — see #202 step 1 (commit 8e0d443) for the shared contract.
/// Forwarding (rather than substitution) keeps the existing view + test
/// surface intact during the migration.
@MainActor
@Observable
final class HeatmapSurveyViewModel {

    // MARK: - MeasurementMode

    enum MeasurementMode: String, CaseIterable {
        case passive    // Wi-Fi signal only (~1-2s)
        case active     // Signal + speed test + ping (~8-10s)
    }

    // MARK: - Shared State

    let state: HeatmapSurveyState

    // MARK: - iOS-Specific State

    var measurementMode: MeasurementMode = .passive
    /// Updated after each user-initiated measurement so the live signal
    /// indicator reflects the most recently sampled value.
    var currentRSSI: Int = -100
    var currentSSID: String?

    // MARK: - Floor Plan (UIKit-typed)

    var showImportSheet: Bool = false
    var showPhotoPicker: Bool = false
    var floorPlanImage: UIImage?

    // MARK: - Visualization Output

    var heatmapImage: CGImage?
    var isHeatmapGenerated: Bool = false

    // MARK: - Canvas

    var canvasScale: CGFloat = 1.0
    var canvasOffset: CGSize = .zero

    // MARK: - Continuous Scan

    var isContinuousScan: Bool = false
    var continuousScanInterval: Double = 3.0
    private var continuousScanTask: Task<Void, Never>?

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
        self.state = HeatmapSurveyState()
        self.heatmapService = service
        self.fileManager = fileManager
        self.exporter = exporter
        renderer = HeatmapRenderer()
    }

    // MARK: - Forwarded State

    var surveyProject: SurveyProject? {
        get { state.surveyProject }
        set { state.surveyProject = newValue }
    }

    var measurementPoints: [MeasurementPoint] {
        get { state.measurementPoints }
        set { state.setMeasurements(newValue) }
    }

    var isSurveying: Bool {
        get { state.isSurveying }
        set { state.isSurveying = newValue }
    }

    var errorMessage: String? {
        get { state.errorMessage }
        set { state.errorMessage = newValue }
    }

    var isMeasuring: Bool {
        get { state.isMeasuring }
        set { state.isMeasuring = newValue }
    }

    var pendingMeasurementLocation: CGPoint? {
        get { state.pendingMeasurementLocation }
        set { state.pendingMeasurementLocation = newValue }
    }

    var selectedVisualization: HeatmapVisualization {
        get { state.selectedVisualization }
        set { state.selectedVisualization = newValue }
    }

    var selectedColorScheme: HeatmapColorScheme {
        get { state.selectedColorScheme }
        set { state.selectedColorScheme = newValue }
    }

    var heatmapOpacity: Double {
        get { state.heatmapOpacity }
        set { state.heatmapOpacity = newValue }
    }

    var isCalibrating: Bool {
        get { state.isCalibrating }
        set { state.isCalibrating = newValue }
    }

    var isCalibrated: Bool {
        get { state.isCalibrated }
        set { state.isCalibrated = newValue }
    }

    var calibrationPoints: [CalibrationPoint] {
        get { state.calibrationPoints }
        set { state.calibrationPoints = newValue }
    }

    var calibrationDistance: Double {
        get { state.calibrationDistance }
        set { state.calibrationDistance = newValue }
    }

    var showCalibrationSheet: Bool {
        get { state.showCalibrationSheet }
        set { state.showCalibrationSheet = newValue }
    }

    var selectedAPFilter: String? {
        get { state.selectedAPFilter }
        set { state.selectedAPFilter = newValue }
    }

    var canUndo: Bool { state.canUndo }

    var uniqueBSSIDs: [(bssid: String, ssid: String)] { state.uniqueBSSIDs }

    var filteredPoints: [MeasurementPoint] { state.filteredPoints }

    var averageRSSI: Double? { state.averageRSSI }

    var minRSSI: Int? { state.minRSSI }

    var maxRSSI: Int? { state.maxRSSI }

    var hasFloorPlan: Bool { state.hasFloorPlan }

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

        let project = SurveyProject(name: name, floorPlan: floorPlan)
        state.setProject(project)
        floorPlanImage = uiImage
        heatmapImage = nil
        isHeatmapGenerated = false
    }

    func importFloorPlan(imageData: Data, width: Int, height: Int) {
        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: Double(width) * 0.01,
            heightMeters: Double(height) * 0.01,
            pixelWidth: width,
            pixelHeight: height,
            origin: .imported
        )
        let project = SurveyProject(name: "Untitled Survey", floorPlan: floorPlan)
        state.setProject(project)
        heatmapImage = nil
        isHeatmapGenerated = false
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
            state.errorMessage = HeatmapError.noFloorPlan.localizedDescription
            return
        }

        let floorPlan = BlueprintSaveLoadManager.floorPlanFromBlueprint(floor)

        let project = SurveyProject(
            name: blueprint.name,
            floorPlan: floorPlan,
            metadata: SurveyMetadata(
                buildingName: blueprint.metadata.buildingName,
                floorNumber: floor.label,
                notes: blueprint.metadata.notes
            )
        )

        // BlueprintSaveLoadManager.floorPlanFromBlueprint doesn't stamp
        // calibrationPoints onto the FloorPlan even though the blueprint is
        // calibrated from RoomPlan dimensions. Force the calibrated path
        // explicitly so the state-machine sees a pre-calibrated project.
        state.setProject(project)
        state.isCalibrated = true
        state.isCalibrating = false

        floorPlanImage = UIImage(data: floorPlan.imageData)
        heatmapImage = nil
        isHeatmapGenerated = false
    }

    // MARK: - Calibration

    func startCalibration() {
        state.startCalibration()
    }

    func cancelCalibration() {
        state.cancelCalibration()
    }

    func skipCalibration() {
        state.skipCalibration()
    }

    func addCalibrationPoint(at normalizedPoint: CGPoint) {
        state.addCalibrationPoint(at: normalizedPoint)
    }

    func completeCalibration(distance: Double, isFeet: Bool) {
        state.completeCalibration(distance: distance, isFeet: isFeet)
    }

    func completeCalibration(withDistance distanceMeters: Double) {
        state.completeCalibration(withDistance: distanceMeters)
    }

    // MARK: - Survey Control

    func startSurvey() {
        guard state.surveyProject != nil, state.isCalibrated else { return }
        state.isSurveying = true
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
        state.isSurveying = false
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
        guard state.surveyProject != nil, !state.isMeasuring else { return }
        state.isMeasuring = true
        state.pendingMeasurementLocation = normalizedPoint
        defer {
            state.isMeasuring = false
            state.pendingMeasurementLocation = nil
        }

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

        state.recordMeasurement(point)
        measurementsSinceLastSave += 1

        // Update live display
        currentRSSI = point.rssi
        currentSSID = point.ssid

        // Auto-update heatmap after 3+ points
        if state.measurementPoints.count >= 3 {
            updateHeatmap()
        }

        // Auto-save every 5 measurements
        if measurementsSinceLastSave >= 5 {
            autoSave()
        }
    }

    // MARK: - Point Management

    func deleteMeasurement(id: UUID) {
        state.deleteMeasurement(id: id)
        if isHeatmapGenerated { updateHeatmap() }
    }

    func clearMeasurements() {
        state.clearMeasurements()
        heatmapImage = nil
        isHeatmapGenerated = false
    }

    // MARK: - Undo

    func undo() {
        state.undo()
        if isHeatmapGenerated { updateHeatmap() }
    }

    // MARK: - Heatmap Generation

    func updateHeatmap() {
        let pointsToRender = state.filteredPoints
        guard !pointsToRender.isEmpty else {
            heatmapImage = nil
            isHeatmapGenerated = false
            return
        }

        let config = HeatmapRenderer.Configuration(opacity: state.heatmapOpacity)
        let localRenderer = HeatmapRenderer(configuration: config)
        let visualization = state.selectedVisualization
        let colorScheme = state.selectedColorScheme

        Task.detached {
            let image = localRenderer.render(
                points: pointsToRender,
                visualization: visualization,
                colorScheme: colorScheme
            )
            await MainActor.run { [weak self] in
                self?.heatmapImage = image
                self?.isHeatmapGenerated = true
            }
        }
    }

    // MARK: - Project Save/Load

    func saveProject(to url: URL) throws {
        guard var project = state.surveyProject else { return }
        isSaving = true
        defer { isSaving = false }

        project.measurementPoints = state.measurementPoints
        try fileManager.save(project: project, to: url)
        lastSaveDate = Date()
        measurementsSinceLastSave = 0
    }

    func loadProject(from url: URL) throws {
        let project = try fileManager.load(from: url)
        state.setProject(project)
        floorPlanImage = UIImage(data: project.floorPlan.imageData)
        if !state.measurementPoints.isEmpty {
            updateHeatmap()
        }
    }

    func autoSave() {
        guard let project = state.surveyProject,
              let saveURL = fileManager.autoSaveURL(for: project.name)
        else { return }
        do {
            try saveProject(to: saveURL)
        } catch {
            state.errorMessage = "Auto-save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    func exportImage(canvasSize: CGSize) -> UIImage? {
        guard state.surveyProject != nil else { return nil }
        return exporter.renderImage(
            floorPlanImage: floorPlanImage,
            heatmapImage: heatmapImage,
            points: state.filteredPoints,
            heatmapOpacity: state.heatmapOpacity,
            canvasSize: canvasSize
        )
    }

    /// Exports the project as a .netmonsurvey file URL for sharing.
    func exportProjectFile() -> URL? {
        guard var project = state.surveyProject else { return nil }
        project.measurementPoints = state.measurementPoints
        return exporter.exportProjectFile(project: project, fileManager: fileManager)
    }
}
