import AppKit
import Foundation
import NetMonitorCore
import Observation
import os
import UniformTypeIdentifiers

// MARK: - CalibrationUnit

/// The distance unit used for scale calibration.
enum CalibrationUnit: String, CaseIterable, Identifiable, Sendable {
    case meters = "Meters"
    case feet = "Feet"

    var id: String { rawValue }

    /// Conversion factor to meters.
    var toMeters: Double {
        switch self {
        case .meters: 1.0
        case .feet: 0.3048
        }
    }
}

// MARK: - SummaryStats

/// Summary statistics for measurement points in the sidebar.
struct SummaryStats: Equatable, Sendable {
    let count: Int
    let minRSSI: Int
    let maxRSSI: Int
    let avgRSSI: Double
    let coverageAreaSqM: Double

    static let empty = SummaryStats(count: 0, minRSSI: 0, maxRSSI: 0, avgRSSI: 0, coverageAreaSqM: 0)
}

// MARK: - UndoAction

/// Represents an undoable action in the heatmap survey.
enum UndoAction: Sendable {
    /// A measurement point was placed.
    case placement(MeasurementPoint)
    /// A measurement point was deleted, along with its original index.
    case deletion(MeasurementPoint, Int)
}

// MARK: - HeatmapSurveyViewModel

/// ViewModel for the macOS heatmap survey workflow.
/// Manages floor plan import, calibration state, survey project,
/// measurement points, live RSSI, summary stats, and canvas state.
@MainActor
@Observable
// swiftlint:disable:next type_body_length
final class HeatmapSurveyViewModel {

    // MARK: - Floor Plan State

    /// The imported floor plan image, or nil if no floor plan loaded.
    private(set) var floorPlanImage: NSImage?

    /// The raw import result with image data and dimensions.
    private(set) var importResult: FloorPlanImportResult?

    /// Whether a floor plan has been imported.
    var hasFloorPlan: Bool { floorPlanImage != nil }

    // MARK: - Calibration State

    /// Whether the calibration sheet is currently shown.
    var isCalibrationSheetPresented = false

    /// First calibration marker position (normalized 0-1).
    var calibrationPoint1 = CGPoint(x: 0.25, y: 0.5)

    /// Second calibration marker position (normalized 0-1).
    var calibrationPoint2 = CGPoint(x: 0.75, y: 0.5)

    /// Real-world distance between the two calibration points.
    var calibrationDistance: String = ""

    /// Unit for the calibration distance.
    var calibrationUnit: CalibrationUnit = .meters

    /// Whether calibration has been completed.
    private(set) var isCalibrated = false

    /// Pixels per meter ratio computed after calibration.
    private(set) var pixelsPerMeter: Double = 0

    // MARK: - Scale Bar

    /// Human-readable scale bar label (e.g., "5 m" or "10 ft").
    private(set) var scaleBarLabel: String = ""

    /// Scale bar width as a fraction of the floor plan width (0-1).
    private(set) var scaleBarFraction: Double = 0

    // MARK: - Project State

    /// The current survey project.
    private(set) var project: SurveyProject?

    /// Error message to display to the user.
    private(set) var errorMessage: String?

    /// Whether the error alert should be shown.
    var showingError = false

    // MARK: - Survey State

    /// Whether a measurement is currently being taken.
    private(set) var isMeasuring = false

    /// The currently selected (highlighted) measurement point ID.
    var selectedPointID: UUID?

    /// Summary statistics for the current measurement points.
    private(set) var summaryStats = SummaryStats.empty

    /// Spacing guidance text shown to the user.
    let spacingGuidanceText = "Place measurements 3–5 meters apart for best coverage"

    // MARK: - Active Scan Mode

    /// Whether active scan mode is enabled (speed test + ping at each point).
    var isActiveScanMode = false

    /// Progress value (0.0 to 1.0) during an active measurement. Nil when not measuring.
    private(set) var activeMeasurementProgress: Double?

    // MARK: - Undo/Redo

    /// Stack of actions that can be undone.
    private(set) var undoStack: [UndoAction] = []

    /// Stack of actions that can be redone.
    private(set) var redoStack: [UndoAction] = []

    /// Whether undo is available.
    var canUndo: Bool { !undoStack.isEmpty }

    /// Whether redo is available.
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Measurement Inspection

    /// The measurement point ID currently being inspected via popover.
    var inspectedPointID: UUID?

    /// The measurement point currently being inspected.
    var inspectedPoint: MeasurementPoint? {
        guard let id = inspectedPointID else { return nil }
        return project?.measurementPoints.first { $0.id == id }
    }

    // MARK: - Visualization State

    /// The currently selected visualization type for the heatmap overlay.
    var selectedVisualization: HeatmapVisualization = .signalStrength {
        didSet {
            renderHeatmapOverlay()
        }
    }

    /// The rendered heatmap overlay image, or nil if fewer than 3 valid points.
    private(set) var heatmapOverlayImage: CGImage?

    /// Whether the current visualization type has valid data for at least 3 measurement points.
    private(set) var visualizationHasData = false

    /// Human-readable display name for the current visualization type.
    var visualizationDisplayName: String {
        switch selectedVisualization {
        case .signalStrength: "Signal Strength"
        case .signalToNoise: "Signal to Noise"
        case .downloadSpeed: "Download Speed"
        case .uploadSpeed: "Upload Speed"
        case .latency: "Latency"
        }
    }

    // MARK: - PDF Export

    /// Whether PDF export is available (requires 3+ measurement points).
    var canExportPDF: Bool {
        guard let points = project?.measurementPoints
        else { return false }
        return points.count >= 3
    }

    // MARK: - File Path Tracking

    /// The URL where the current project was last saved to or loaded from.
    /// Used for overwriting an existing file on subsequent saves.
    private(set) var currentSavePath: URL?

    // MARK: - Canvas State

    /// Current zoom scale (1.0 = no zoom).
    var zoomScale: CGFloat = 1.0

    /// Current pan offset.
    var panOffset: CGSize = .zero

    // MARK: - Live RSSI

    /// Live RSSI reading from CoreWLAN (updated at 1Hz).
    private(set) var liveRSSI: Int?

    /// Formatted RSSI badge text for the toolbar.
    var liveRSSIBadgeText: String {
        guard let rssi = liveRSSI
        else { return "No WiFi" }
        return "\(rssi) dBm"
    }

    /// Timer for live RSSI updates.
    private var rssiTimer: Timer?

    // MARK: - Dependencies

    /// The measurement engine for taking WiFi measurements.
    private let measurementEngine: (any HeatmapServiceProtocol)?

    /// The CoreWLAN service for live RSSI readings.
    private let coreWLANService: (any CoreWLANServiceProtocol)?

    // MARK: - Init

    init(
        measurementEngine: (any HeatmapServiceProtocol)? = nil,
        coreWLANService: (any CoreWLANServiceProtocol)? = nil
    ) {
        self.measurementEngine = measurementEngine
        self.coreWLANService = coreWLANService
    }

    // MARK: - Floor Plan Import

    /// Opens an NSOpenPanel for the user to select a floor plan image.
    func importFloorPlan() {
        guard let url = FloorPlanImporter.presentOpenPanel()
        else { return }

        loadFloorPlan(from: url)
    }

    /// Loads a floor plan from a file URL (used by both import and drag-and-drop).
    func loadFloorPlan(from url: URL) {
        do {
            let result = try FloorPlanImporter.importFloorPlan(from: url)
            applyImportResult(result)
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Handles drag-and-drop of files onto the floor plan area.
    /// Returns true if the drop was handled successfully.
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first
        else { return false }

        // Try to load as file URL
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    Task { @MainActor in
                        self?.showError(error?.localizedDescription ?? "Failed to read dropped file")
                    }
                    return
                }

                Task { @MainActor [weak self] in
                    if FloorPlanImporter.isSupported(url) {
                        self?.loadFloorPlan(from: url)
                    } else {
                        self?.showError("Unsupported file format: \(url.pathExtension)")
                    }
                }
            }
            return true
        }

        return false
    }

    // MARK: - Calibration

    /// Begins the calibration workflow by presenting the calibration sheet.
    func startCalibration() {
        guard hasFloorPlan
        else { return }

        // Reset calibration markers to sensible defaults
        calibrationPoint1 = CGPoint(x: 0.25, y: 0.5)
        calibrationPoint2 = CGPoint(x: 0.75, y: 0.5)
        calibrationDistance = ""
        calibrationUnit = .meters
        isCalibrationSheetPresented = true
    }

    /// Applies the calibration using the current marker positions and distance.
    func applyCalibration() {
        guard let result = importResult,
              let distanceValue = Double(calibrationDistance),
              distanceValue > 0
        else {
            showError("Please enter a valid distance greater than zero")
            return
        }

        let distanceInMeters = distanceValue * calibrationUnit.toMeters

        // Compute pixel distance between the two calibration points
        let dx = (calibrationPoint2.x - calibrationPoint1.x) * Double(result.pixelWidth)
        let dy = (calibrationPoint2.y - calibrationPoint1.y) * Double(result.pixelHeight)
        let pixelDistance = sqrt(dx * dx + dy * dy)

        guard pixelDistance > 0
        else {
            showError("Calibration points must be at different locations")
            return
        }

        pixelsPerMeter = pixelDistance / distanceInMeters
        isCalibrated = true
        isCalibrationSheetPresented = false

        // Update floor plan dimensions in the project
        if var currentProject = project {
            let widthMeters = Double(result.pixelWidth) / pixelsPerMeter
            let heightMeters = Double(result.pixelHeight) / pixelsPerMeter
            currentProject.floorPlan.widthMeters = widthMeters
            currentProject.floorPlan.heightMeters = heightMeters
            currentProject.floorPlan.calibrationPoints = [
                CalibrationPoint(
                    pixelX: calibrationPoint1.x * Double(result.pixelWidth),
                    pixelY: calibrationPoint1.y * Double(result.pixelHeight),
                    realWorldX: 0,
                    realWorldY: 0
                ),
                CalibrationPoint(
                    pixelX: calibrationPoint2.x * Double(result.pixelWidth),
                    pixelY: calibrationPoint2.y * Double(result.pixelHeight),
                    realWorldX: distanceInMeters,
                    realWorldY: 0
                )
            ]
            project = currentProject
        }

        computeScaleBar()

        Logger.app.debug("Calibration complete: \(self.pixelsPerMeter, format: .fixed(precision: 2)) px/m")
    }

    /// Skips calibration and proceeds with pixel coordinates.
    func skipCalibration() {
        isCalibrationSheetPresented = false
        isCalibrated = false
        pixelsPerMeter = 0
        scaleBarLabel = ""
        scaleBarFraction = 0
    }

    // MARK: - Survey Measurement

    /// Takes a WiFi measurement at the given normalized position on the floor plan.
    /// In active scan mode, runs a speed test + ping. In passive mode, captures WiFi info only.
    func takeMeasurement(at normalizedPoint: CGPoint) async {
        guard var currentProject = project,
              let engine = measurementEngine
        else { return }

        isMeasuring = true
        defer {
            isMeasuring = false
            activeMeasurementProgress = nil
        }

        let point: MeasurementPoint
        if isActiveScanMode {
            activeMeasurementProgress = 0.0
            // Simulate progress updates during the ~6s active measurement
            let progressTask = Task { @MainActor [weak self] in
                for step in 1...5 {
                    try? await Task.sleep(for: .seconds(1))
                    self?.activeMeasurementProgress = Double(step) / 6.0
                }
            }
            point = await engine.takeActiveMeasurement(
                at: normalizedPoint.x,
                floorPlanY: normalizedPoint.y
            )
            progressTask.cancel()
            activeMeasurementProgress = 1.0
        } else {
            point = await engine.takeMeasurement(
                at: normalizedPoint.x,
                floorPlanY: normalizedPoint.y
            )
        }

        // Detect Wi-Fi disconnection: nil SSID combined with default -100 RSSI
        // indicates no Wi-Fi connection. Show an error instead of adding garbage data.
        if point.ssid == nil && point.rssi <= -100 {
            showError("Wi-Fi is not connected. Connect to a Wi-Fi network before measuring.")
            return
        }

        currentProject.measurementPoints.append(point)
        project = currentProject

        // Push to undo stack and clear redo
        undoStack.append(.placement(point))
        redoStack.removeAll()

        recalculateStats()
        renderHeatmapOverlay()
    }

    /// Removes a measurement point by its ID, recording the action for undo.
    func removeMeasurementPoint(id: UUID) {
        guard var currentProject = project
        else { return }

        guard let index = currentProject.measurementPoints.firstIndex(where: { $0.id == id })
        else { return }

        let removedPoint = currentProject.measurementPoints.remove(at: index)

        if selectedPointID == id {
            selectedPointID = nil
        }
        if inspectedPointID == id {
            inspectedPointID = nil
        }

        project = currentProject

        // Push to undo stack and clear redo
        undoStack.append(.deletion(removedPoint, index))
        redoStack.removeAll()

        recalculateStats()
        renderHeatmapOverlay()
    }

    // MARK: - State Reset

    /// Resets calibration, undo/redo, selection, and overlay state for a new or loaded project.
    func resetProjectState() {
        isCalibrated = false
        pixelsPerMeter = 0
        scaleBarLabel = ""
        scaleBarFraction = 0
        currentSavePath = nil
        undoStack.removeAll()
        redoStack.removeAll()
        selectedPointID = nil
        inspectedPointID = nil
        heatmapOverlayImage = nil
        summaryStats = .empty
    }

    // MARK: - Undo / Redo

    /// Undoes the last action (placement or deletion).
    func undo() {
        guard var currentProject = project, let action = undoStack.popLast()
        else { return }

        switch action {
        case .placement(let point):
            // Undo a placement by removing the point
            currentProject.measurementPoints.removeAll { $0.id == point.id }
            redoStack.append(.placement(point))

        case .deletion(let point, let index):
            // Undo a deletion by re-inserting the point at its original position
            let safeIndex = min(index, currentProject.measurementPoints.count)
            currentProject.measurementPoints.insert(point, at: safeIndex)
            redoStack.append(.deletion(point, index))
        }

        project = currentProject
        recalculateStats()
        renderHeatmapOverlay()
    }

    /// Redoes the last undone action.
    func redo() {
        guard var currentProject = project, let action = redoStack.popLast()
        else { return }

        switch action {
        case .placement(let point):
            // Redo a placement by adding the point back
            currentProject.measurementPoints.append(point)
            undoStack.append(.placement(point))

        case .deletion(let point, let index):
            // Redo a deletion by removing the point again
            currentProject.measurementPoints.removeAll { $0.id == point.id }
            undoStack.append(.deletion(point, index))
        }

        project = currentProject
        recalculateStats()
        renderHeatmapOverlay()
    }

    // MARK: - Save / Load

    /// Saves the current project via NSSavePanel, or overwrites the existing path
    /// if the project was previously saved or loaded.
    func saveProject() {
        guard let currentProject = project
        else { return }

        // If we already have a save path, overwrite directly
        if let existingPath = currentSavePath {
            do {
                try SurveyFileManager.save(currentProject, to: existingPath)
                Logger.app.info("Survey project overwritten at \(existingPath.lastPathComponent)")
                return
            } catch {
                // Fall through to NSSavePanel if overwrite fails
                Logger.app.warning("Overwrite failed, showing save panel: \(error.localizedDescription)")
            }
        }

        let panel = NSSavePanel()
        panel.title = "Save Survey Project"
        panel.prompt = "Save"
        panel.nameFieldStringValue = "\(currentProject.name).netmonsurvey"
        panel.allowedContentTypes = [.init(exportedAs: "com.netmonitor.survey")]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url
        else { return }

        do {
            try SurveyFileManager.save(currentProject, to: url)
            currentSavePath = url
            Logger.app.info("Survey project saved to \(url.lastPathComponent)")
        } catch {
            showError("Failed to save project: \(error.localizedDescription)")
        }
    }

    /// Saves the current project to a new location via NSSavePanel (always shows panel).
    func saveProjectAs() {
        guard let currentProject = project
        else { return }

        let panel = NSSavePanel()
        panel.title = "Save Survey Project As"
        panel.prompt = "Save"
        panel.nameFieldStringValue = "\(currentProject.name).netmonsurvey"
        panel.allowedContentTypes = [.init(exportedAs: "com.netmonitor.survey")]

        let response = panel.runModal()
        guard response == .OK, let url = panel.url
        else { return }

        do {
            try SurveyFileManager.save(currentProject, to: url)
            currentSavePath = url
            Logger.app.info("Survey project saved as \(url.lastPathComponent)")
        } catch {
            showError("Failed to save project: \(error.localizedDescription)")
        }
    }

    /// Loads a project via NSOpenPanel.
    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Survey Project"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.init(exportedAs: "com.netmonitor.survey")]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url
        else { return }

        loadProject(from: url)
    }

    /// Loads a project from a bundle URL.
    func loadProject(from url: URL) {
        do {
            let loadedProject = try SurveyFileManager.load(from: url)

            // Restore the floor plan image
            let imageData = loadedProject.floorPlan.imageData
            guard let nsImage = NSImage(data: imageData)
            else {
                showError("Failed to decode floor plan image from project file.")
                return
            }

            floorPlanImage = nsImage
            importResult = FloorPlanImportResult(
                imageData: imageData,
                pixelWidth: loadedProject.floorPlan.pixelWidth,
                pixelHeight: loadedProject.floorPlan.pixelHeight,
                sourceURL: url
            )
            project = loadedProject
            currentSavePath = url

            // Restore calibration state
            if let calibrationPoints = loadedProject.floorPlan.calibrationPoints, calibrationPoints.count >= 2,
               loadedProject.floorPlan.widthMeters > 0 {
                pixelsPerMeter = Double(loadedProject.floorPlan.pixelWidth) / loadedProject.floorPlan.widthMeters
                isCalibrated = true
                computeScaleBar()
            } else {
                isCalibrated = false
                pixelsPerMeter = 0
            }

            // Reset undo/redo stacks
            undoStack.removeAll()
            redoStack.removeAll()

            recalculateStats()
            renderHeatmapOverlay()

            Logger.app.info("Survey project loaded from \(url.lastPathComponent)")
        } catch {
            showError("Failed to open project: \(error.localizedDescription)")
        }
    }

    // MARK: - PDF Export

    /// Exports the current survey project as a 3-page PDF report.
    /// Requires 3+ measurement points. Shows NSSavePanel for destination.
    func exportPDF() {
        guard let currentProject = project, let image = floorPlanImage
        else { return }

        guard canExportPDF
        else {
            showError("At least 3 measurement points are required to export a PDF report.")
            return
        }

        guard let pdfData = HeatmapPDFExporter.generatePDF(
            project: currentProject,
            floorPlanImage: image,
            heatmapOverlay: heatmapOverlayImage,
            visualization: selectedVisualization
        ) else {
            showError("Failed to generate PDF report.")
            return
        }

        let success = HeatmapPDFExporter.saveWithPanel(
            pdfData: pdfData,
            projectName: currentProject.name
        )

        if !success {
            // User cancelled — not an error
            Logger.app.debug("PDF export cancelled by user")
        }
    }

    // MARK: - New Project

    /// Creates a new project with the given name and a blank white canvas as the floor plan.
    func createNewProject(name: String, canvasWidth: Int = 1000, canvasHeight: Int = 800) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: canvasWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            showError("Failed to create canvas for new project")
            return
        }

        // Fill white background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

        guard let filledImage = context.makeImage()
        else {
            showError("Failed to create canvas image")
            return
        }

        let rep = NSBitmapImageRep(cgImage: filledImage)
        let pngData = rep.representation(using: .png, properties: [:]) ?? Data()

        applyFloorPlanData(
            name: name,
            imageData: pngData,
            pixelWidth: canvasWidth,
            pixelHeight: canvasHeight,
            origin: .drawn
        )
        Logger.app.info("New project created: \(name)")
    }

    /// Opens an NSOpenPanel for a floor plan image and creates a new project with the given name.
    func importFloorPlanForNewProject(name: String) {
        guard let url = FloorPlanImporter.presentOpenPanel()
        else { return }

        do {
            let result = try FloorPlanImporter.importFloorPlan(from: url)
            applyFloorPlanData(
                name: name,
                imageData: result.imageData,
                pixelWidth: result.pixelWidth,
                pixelHeight: result.pixelHeight,
                origin: .imported(result.sourceURL),
                sourceURL: result.sourceURL
            )
            Logger.app.info("New project '\(name)' created with imported floor plan")
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Applies a drawn floor plan image as the base for a new project.
    func applyDrawnFloorPlan(name: String, imageData: Data) {
        guard !imageData.isEmpty,
              let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            showError("Failed to create floor plan from drawing")
            return
        }

        applyFloorPlanData(
            name: name,
            imageData: imageData,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            origin: .drawn
        )
        Logger.app.info("New project '\(name)' created with drawn floor plan")
    }

    /// Shared helper to apply floor plan data and create a new project.
    private func applyFloorPlanData(
        name: String,
        imageData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        origin: FloorPlanOrigin,
        sourceURL: URL? = nil
    ) {
        let floorPlan = FloorPlan(
            imageData: imageData,
            widthMeters: 0,
            heightMeters: 0,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            origin: origin
        )

        project = SurveyProject(
            name: name,
            floorPlan: floorPlan
        )

        floorPlanImage = NSImage(data: imageData)
        importResult = FloorPlanImportResult(
            imageData: imageData,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            sourceURL: sourceURL ?? URL(fileURLWithPath: "/tmp/drawn-\(name)")
        )

        resetProjectState()
    }

    // MARK: - Live RSSI

    /// Manually refreshes the live RSSI reading from CoreWLAN.
    func refreshLiveRSSI() {
        liveRSSI = coreWLANService?.currentRSSI()
    }

    /// Starts the 1Hz live RSSI update timer.
    func startLiveRSSIUpdates() {
        stopLiveRSSIUpdates()
        refreshLiveRSSI()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLiveRSSI()
            }
        }
    }

    /// Stops the live RSSI update timer.
    func stopLiveRSSIUpdates() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    // MARK: - Error Handling

    /// Shows an error message to the user.
    func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    /// Clears the current error message.
    func clearError() {
        errorMessage = nil
        showingError = false
    }

    // MARK: - Heatmap Overlay Rendering

    /// Re-renders the heatmap overlay using HeatmapRenderer.
    /// Called when measurement points change or visualization type switches.
    /// Produces a CGImage overlay at 70% opacity, or nil if fewer than 3 valid points.
    func renderHeatmapOverlay() {
        guard let points = project?.measurementPoints, let result = importResult
        else {
            heatmapOverlayImage = nil
            visualizationHasData = false
            return
        }

        // Check if current visualization has valid data for at least 3 points
        let validCount = points.filter { pointHasData($0, for: selectedVisualization) }.count
        visualizationHasData = validCount >= 3

        guard visualizationHasData
        else {
            heatmapOverlayImage = nil
            return
        }

        heatmapOverlayImage = HeatmapRenderer.render(
            points: points,
            floorPlanWidth: result.pixelWidth,
            floorPlanHeight: result.pixelHeight,
            visualization: selectedVisualization,
            opacity: 0.7,
            colorScheme: .standard
        )
    }

    /// Checks whether a measurement point has valid data for the given visualization type.
    private func pointHasData(_ point: MeasurementPoint, for visualization: HeatmapVisualization) -> Bool {
        HeatmapRenderer.extractValue(from: point, for: visualization) != nil
    }

    // MARK: - Private Helpers

    /// Recalculates summary statistics from the current measurement points.
    func recalculateStats() {
        guard let points = project?.measurementPoints, !points.isEmpty
        else {
            summaryStats = .empty
            return
        }

        let rssiValues = points.map(\.rssi)
        let minRSSI = rssiValues.min() ?? 0
        let maxRSSI = rssiValues.max() ?? 0
        let avgRSSI = Double(rssiValues.reduce(0, +)) / Double(rssiValues.count)

        // Estimate coverage area: each point covers roughly a circle of 3m radius
        let coveragePerPoint = Double.pi * 3.0 * 3.0 // ~28.3 sq meters
        let coverageAreaSqM = Double(points.count) * coveragePerPoint

        summaryStats = SummaryStats(
            count: points.count,
            minRSSI: minRSSI,
            maxRSSI: maxRSSI,
            avgRSSI: avgRSSI,
            coverageAreaSqM: coverageAreaSqM
        )
    }

    /// Applies the import result and creates a new project.
    private func applyImportResult(_ result: FloorPlanImportResult) {
        importResult = result
        floorPlanImage = NSImage(data: result.imageData)

        // Reset calibration
        isCalibrated = false
        pixelsPerMeter = 0
        scaleBarLabel = ""
        scaleBarFraction = 0

        // Create a new project with the imported floor plan
        let floorPlan = FloorPlan(
            imageData: result.imageData,
            widthMeters: 0,
            heightMeters: 0,
            pixelWidth: result.pixelWidth,
            pixelHeight: result.pixelHeight,
            origin: .imported(result.sourceURL)
        )

        project = SurveyProject(
            name: result.sourceURL.deletingPathExtension().lastPathComponent,
            floorPlan: floorPlan
        )
    }

    /// Computes scale bar parameters for display.
    func computeScaleBar() {
        guard isCalibrated, pixelsPerMeter > 0, let result = importResult
        else { return }

        // Choose a round number for the scale bar distance
        let floorPlanWidthMeters = Double(result.pixelWidth) / pixelsPerMeter
        let targetBarFraction = 0.2 // aim for ~20% of image width
        let targetDistanceMeters = floorPlanWidthMeters * targetBarFraction

        // Round to a nice number
        let roundedDistance: Double
        if targetDistanceMeters >= 10 {
            roundedDistance = (targetDistanceMeters / 5).rounded() * 5
        } else if targetDistanceMeters >= 1 {
            roundedDistance = targetDistanceMeters.rounded()
        } else {
            roundedDistance = (targetDistanceMeters * 10).rounded() / 10
        }

        let barPixels = roundedDistance * pixelsPerMeter
        scaleBarFraction = barPixels / Double(result.pixelWidth)

        if calibrationUnit == .feet {
            let feetValue = roundedDistance / CalibrationUnit.feet.toMeters
            scaleBarLabel = "\(Int(feetValue)) ft"
        } else {
            if roundedDistance >= 1 {
                scaleBarLabel = "\(Int(roundedDistance)) m"
            } else {
                scaleBarLabel = String(format: "%.1f m", roundedDistance)
            }
        }
    }
}
