import CoreGraphics
import Foundation
import NetMonitorCore
import os
import UIKit

// MARK: - HeatmapSurveyViewModel

/// ViewModel for the iOS heatmap walk survey.
/// Manages the full survey lifecycle: tap-to-measure, heatmap rendering,
/// visualization switching, point inspection/deletion, and project save/load.
@MainActor
@Observable
final class HeatmapSurveyViewModel {

    // MARK: - Observable State

    /// The current survey project.
    private(set) var project: SurveyProject

    /// The floor plan UIImage for display.
    private(set) var floorPlanImage: UIImage?

    /// Whether a measurement is currently in progress.
    private(set) var isMeasuring = false

    /// The rendered heatmap overlay image (nil if <3 points).
    private(set) var heatmapOverlay: CGImage?

    /// Current visualization type.
    var selectedVisualization: HeatmapVisualization = .signalStrength {
        didSet { renderHeatmapOverlay() }
    }

    /// The currently inspected measurement point (tap to inspect).
    var inspectedPoint: MeasurementPoint?

    /// Whether the visualization picker bottom sheet is shown.
    var showVisualizationPicker = false

    /// Error message for display.
    var errorMessage: String?

    /// Live RSSI value from the HUD polling.
    private(set) var liveRSSI: Int?

    /// Live SSID from the HUD polling.
    private(set) var liveSSID: String?

    /// Total measurement point count.
    var pointCount: Int { project.measurementPoints.count }

    /// Whether the heatmap overlay should be shown (3+ points).
    var showHeatmap: Bool { project.measurementPoints.count >= 3 }

    /// Spacing guidance text.
    var spacingGuidance: String {
        if project.measurementPoints.isEmpty {
            return "Tap on the floor plan to place your first measurement point"
        } else if project.measurementPoints.count < 3 {
            return "Place at least 3 points to generate a heatmap. Space points 3–5 meters apart."
        } else {
            return "Space measurement points 3–5 meters apart for best coverage"
        }
    }

    /// Available visualization types for iOS (no SNR — iOS limitation).
    let availableVisualizations: [HeatmapVisualization] = [
        .signalStrength,
        .downloadSpeed,
        .latency
    ]

    // MARK: - Private

    private let measurementEngine: any HeatmapServiceProtocol
    private let fileManager: SurveyFileManager.Type
    private var hudPollingTask: Task<Void, Never>?
    private let wifiService: any WiFiInfoServiceProtocol

    // MARK: - Init

    init(
        project: SurveyProject,
        measurementEngine: any HeatmapServiceProtocol,
        wifiService: any WiFiInfoServiceProtocol = WiFiInfoService(),
        fileManager: SurveyFileManager.Type = SurveyFileManager.self
    ) {
        self.project = project
        self.measurementEngine = measurementEngine
        self.wifiService = wifiService
        self.fileManager = fileManager

        // Load floor plan image from project data
        if let image = UIImage(data: project.floorPlan.imageData) {
            self.floorPlanImage = image
        }
    }

    // MARK: - Tap to Measure

    /// Takes a passive measurement at the given normalized floor plan coordinates.
    /// Called when user taps on the canvas.
    func takeMeasurement(atNormalizedX x: Double, y: Double) async {
        guard !isMeasuring else { return }

        isMeasuring = true
        defer { isMeasuring = false }

        let point = await measurementEngine.takeMeasurement(at: x, floorPlanY: y)

        // Check for Wi-Fi disconnect (nil SSID + very low RSSI)
        if point.ssid == nil, point.rssi <= -100 {
            errorMessage = "Wi-Fi is not connected. Connect to a Wi-Fi network before measuring."
            return
        }

        project.measurementPoints.append(point)
        renderHeatmapOverlay()

        Logger.heatmap.debug("Measurement placed at (\(x, format: .fixed(precision: 2)), \(y, format: .fixed(precision: 2))), RSSI: \(point.rssi)")
    }

    // MARK: - Point Management

    /// Deletes a measurement point and re-renders the heatmap.
    func deletePoint(_ point: MeasurementPoint) {
        project.measurementPoints.removeAll { $0.id == point.id }
        inspectedPoint = nil
        renderHeatmapOverlay()
    }

    /// Selects a point for inspection.
    func inspectPoint(_ point: MeasurementPoint) {
        inspectedPoint = point
    }

    // MARK: - Heatmap Rendering

    /// Renders the heatmap overlay using the shared HeatmapRenderer.
    func renderHeatmapOverlay() {
        guard project.measurementPoints.count >= 3 else {
            heatmapOverlay = nil
            return
        }

        // Use floor plan pixel dimensions for output
        let width = project.floorPlan.pixelWidth
        let height = project.floorPlan.pixelHeight

        guard width > 0, height > 0 else {
            heatmapOverlay = nil
            return
        }

        heatmapOverlay = HeatmapRenderer.render(
            points: project.measurementPoints,
            floorPlanWidth: width,
            floorPlanHeight: height,
            visualization: selectedVisualization,
            opacity: 0.7
        )
    }

    // MARK: - Live RSSI HUD Polling

    /// Starts polling the Wi-Fi service at 1Hz for live RSSI updates.
    func startHUDPolling() {
        stopHUDPolling()

        hudPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let wifiInfo = await self.wifiService.fetchCurrentWiFi()
                if !Task.isCancelled {
                    self.liveRSSI = wifiInfo?.signalDBm
                    self.liveSSID = wifiInfo?.ssid
                }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    /// Stops the live RSSI polling task.
    func stopHUDPolling() {
        hudPollingTask?.cancel()
        hudPollingTask = nil
    }

    // MARK: - Save Project

    /// Saves the project to the app's Documents directory as a .netmonsurvey bundle.
    func saveProject() {
        let documentsURL = Foundation.FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        // Sanitize project name for filename
        let safeName = project.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = safeName.isEmpty ? "Untitled" : safeName
        let bundleURL = documentsURL.appendingPathComponent("\(fileName).netmonsurvey")

        do {
            try fileManager.save(project, to: bundleURL)
            Logger.heatmap.debug("Project saved to \(bundleURL.lastPathComponent)")
        } catch {
            errorMessage = "Failed to save project: \(error.localizedDescription)"
            Logger.heatmap.error("Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Load Project

    /// Loads a project from a .netmonsurvey bundle URL.
    static func loadProject(
        from bundleURL: URL,
        measurementEngine: any HeatmapServiceProtocol,
        wifiService: any WiFiInfoServiceProtocol = WiFiInfoService()
    ) -> HeatmapSurveyViewModel? {
        do {
            let project = try SurveyFileManager.load(from: bundleURL)
            let viewModel = HeatmapSurveyViewModel(
                project: project,
                measurementEngine: measurementEngine,
                wifiService: wifiService
            )
            viewModel.renderHeatmapOverlay()
            return viewModel
        } catch {
            Logger.heatmap.error("Load failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Summary Statistics

    /// Average RSSI across all measurement points.
    var averageRSSI: Int? {
        let points = project.measurementPoints
        guard !points.isEmpty else { return nil }
        let total = points.reduce(0) { $0 + $1.rssi }
        return total / points.count
    }

    /// Minimum (worst) RSSI across all measurement points.
    var minRSSI: Int? {
        project.measurementPoints.map(\.rssi).min()
    }

    /// Maximum (best) RSSI across all measurement points.
    var maxRSSI: Int? {
        project.measurementPoints.map(\.rssi).max()
    }
}
