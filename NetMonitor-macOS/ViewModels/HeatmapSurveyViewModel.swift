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

// MARK: - HeatmapSurveyViewModel

/// ViewModel for the macOS heatmap survey workflow.
/// Manages floor plan import, calibration state, survey project,
/// measurement points, live RSSI, summary stats, and canvas state.
@MainActor
@Observable
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
    /// Creates a MeasurementPoint and adds it to the project.
    func takeMeasurement(at normalizedPoint: CGPoint) async {
        guard var currentProject = project,
              let engine = measurementEngine
        else { return }

        isMeasuring = true
        defer { isMeasuring = false }

        let point = await engine.takeMeasurement(
            at: normalizedPoint.x,
            floorPlanY: normalizedPoint.y
        )
        currentProject.measurementPoints.append(point)
        project = currentProject
        recalculateStats()
    }

    /// Removes a measurement point by its ID.
    func removeMeasurementPoint(id: UUID) {
        guard var currentProject = project
        else { return }

        currentProject.measurementPoints.removeAll { $0.id == id }
        if selectedPointID == id {
            selectedPointID = nil
        }
        project = currentProject
        recalculateStats()
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

    // MARK: - Private Helpers

    /// Recalculates summary statistics from the current measurement points.
    private func recalculateStats() {
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
    private func computeScaleBar() {
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
