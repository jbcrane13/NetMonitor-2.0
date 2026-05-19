import AppKit
import Foundation
import NetMonitorCore
import SwiftUI

// MARK: - WiFiHeatmapViewModel

@MainActor
@Observable
final class WiFiHeatmapViewModel {

    // MARK: - Shared State

    let state: HeatmapSurveyState

    // MARK: - Live Signal (macOS-only)

    private(set) var currentSignal: SignalSnapshot?
    private(set) var nearbyAPs: [NearbyAP] = []
    private(set) var isScanning: Bool = false

    // MARK: - Sidebar State (macOS-only)

    enum SidebarMode: String, CaseIterable {
        case survey
        case analyze
    }

    var sidebarMode: SidebarMode = .survey
    var isSidebarCollapsed: Bool = false

    // MARK: - Coverage Threshold (macOS-only)

    var coverageThreshold: Double = -70 // dBm
    var isCoverageThresholdEnabled: Bool = false

    // MARK: - Measurement Mode

    enum MeasurementMode: String, CaseIterable {
        case passive
        case active
    }

    var measurementMode: MeasurementMode = .passive
    var isContinuousScan: Bool = false
    var continuousScanInterval: Double = 3.0
    private(set) var liveCursorLocation: CGPoint?
    private var continuousScanTask: Task<Void, Never>?

    // MARK: - Canvas (macOS-only)

    var heatmapCGImage: CGImage?
    var showImportSheet: Bool = false
    var showPhotoPicker: Bool = false
    var isHeatmapGenerated: Bool = false

    // MARK: - Services

    private let heatmapService: any MacWiFiSignalProviding
    private var wifiEngine: WiFiMeasurementEngine?
    private var signalPollTask: Task<Void, Never>?
    private let renderer: HeatmapRenderer

    // MARK: - Init

    init(heatmapService: any MacWiFiSignalProviding = WiFiHeatmapService()) {
        self.state = HeatmapSurveyState()
        self.heatmapService = heatmapService
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

    // MARK: - Forwarded State

    var errorMessage: String? {
        get { state.errorMessage }
        set { state.errorMessage = newValue }
    }

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

    var isMeasuring: Bool {
        get { state.isMeasuring }
        set { state.isMeasuring = newValue }
    }

    var pendingMeasurementLocation: CGPoint? {
        get { state.pendingMeasurementLocation }
        set { state.pendingMeasurementLocation = newValue }
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

    var showCalibrationSheet: Bool {
        get { state.showCalibrationSheet }
        set { state.showCalibrationSheet = newValue }
    }

    var selectedVisualization: HeatmapVisualization {
        get { state.selectedVisualization }
        set { state.selectedVisualization = newValue }
    }

    /// macOS legacy name for the shared `selectedColorScheme`.
    var colorScheme: HeatmapColorScheme {
        get { state.selectedColorScheme }
        set { state.selectedColorScheme = newValue }
    }

    /// macOS legacy name for the shared `heatmapOpacity`.
    var overlayOpacity: Double {
        get { state.heatmapOpacity }
        set { state.heatmapOpacity = newValue }
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
        guard !isScanning else { return }
        isScanning = true
        let service = heatmapService
        Task { [weak self] in
            let aps = await service.scanForNearbyAPs()
            self?.nearbyAPs = aps
            self?.isScanning = false
        }
    }

    // MARK: - Survey Control

    func startSurvey() {
        guard state.surveyProject != nil, state.isCalibrated else { return }
        state.isSurveying = true
        sidebarMode = .survey
        isHeatmapGenerated = false
        heatmapCGImage = nil
        if isContinuousScan {
            startContinuousScanTimer()
        }
    }

    func stopSurvey() {
        state.isSurveying = false
        stopContinuousScanTimer()
        generateHeatmap()
    }

    private func startContinuousScanTimer() {
        continuousScanTask?.cancel()
        continuousScanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.continuousScanInterval))
                if Task.isCancelled { return }
                guard self.isSurveying, let loc = self.liveCursorLocation else { continue }
                await self.takeMeasurement(at: loc)
            }
        }
    }

    private func stopContinuousScanTimer() {
        continuousScanTask?.cancel()
        continuousScanTask = nil
    }

    func updateCursorLocation(_ point: CGPoint) {
        liveCursorLocation = point
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

        state.recordMeasurement(point)
    }

    // MARK: - Heatmap Generation

    func generateHeatmap() {
        let pointsToRender = state.filteredPoints
        guard !pointsToRender.isEmpty else {
            heatmapCGImage = nil
            isHeatmapGenerated = false
            return
        }

        let config = HeatmapRenderer.Configuration(opacity: state.heatmapOpacity)
        let localRenderer = HeatmapRenderer(configuration: config)
        let visualization = state.selectedVisualization
        let scheme = state.selectedColorScheme

        Task.detached {
            let image = localRenderer.render(
                points: pointsToRender,
                visualization: visualization,
                colorScheme: scheme
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

        let project = SurveyProject(
            name: url.deletingPathExtension().lastPathComponent,
            floorPlan: floorPlan
        )
        state.setProject(project)
        heatmapCGImage = nil
        isHeatmapGenerated = false
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

        let project = SurveyProject(name: name, floorPlan: floorPlan)
        state.setProject(project)
        heatmapCGImage = nil
        isHeatmapGenerated = false
    }

    // MARK: - Blueprint Import

    func importBlueprint(from url: URL) throws {
        let manager = BlueprintSaveLoadManager()
        let blueprint = try manager.load(from: url)

        guard let floor = blueprint.floors.first else {
            throw HeatmapError.noFloorPlan
        }

        // Convert blueprint floor to a FloorPlan (pre-calibrated, no manual calibration needed)
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

        // floorPlanFromBlueprint doesn't stamp calibrationPoints onto the
        // FloorPlan, so state.setProject would treat this as needing
        // calibration. Force the calibrated path explicitly.
        state.setProject(project)
        state.isCalibrated = true
        state.isCalibrating = false

        heatmapCGImage = nil
        isHeatmapGenerated = false
    }

    // MARK: - Calibration

    func startCalibration() {
        state.startCalibration()
    }

    func cancelCalibration() {
        state.cancelCalibration()
    }

    func addCalibrationPoint(at normalizedPoint: CGPoint) {
        state.addCalibrationPoint(at: normalizedPoint)
    }

    func completeCalibration(withDistance distance: Double) {
        state.completeCalibration(withDistance: distance)
    }

    // MARK: - Undo / Point Management

    func undo() {
        state.undo()
        if isHeatmapGenerated { generateHeatmap() }
    }

    func deletePoint(id: UUID) {
        state.deleteMeasurement(id: id)
        if isHeatmapGenerated { generateHeatmap() }
    }

    func clearMeasurements() {
        state.clearMeasurements()
        heatmapCGImage = nil
        isHeatmapGenerated = false
    }

    // MARK: - Project Save/Load

    func saveProject(to url: URL) throws {
        guard var project = state.surveyProject else { return }
        project.measurementPoints = state.measurementPoints
        let manager = ProjectSaveLoadManager()
        try manager.save(project: project, to: url)
    }

    func loadProject(from url: URL) throws {
        let manager = ProjectSaveLoadManager()
        let project = try manager.load(from: url)
        state.setProject(project)
        if !state.measurementPoints.isEmpty {
            generateHeatmap()
        }
    }
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
