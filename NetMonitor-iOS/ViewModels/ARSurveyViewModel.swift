import CoreGraphics
import Foundation
import NetMonitorCore
import os
import UIKit

// MARK: - ARTrackingStatus

/// Tracks the AR camera tracking quality during survey.
enum ARTrackingStatus: Sendable, Equatable {
    /// Tracking is working normally — auto-position available.
    case normal
    /// Tracking quality is limited — auto-position hidden.
    case limited(reason: String)
    /// Tracking is not available — manual fallback mode.
    case notAvailable
}

// MARK: - FloorPlanEditAction

/// An individual floor plan editing action.
enum FloorPlanEditAction: Sendable, Equatable, Identifiable {
    case dragWallEndpoint(wallIndex: Int, endpointIndex: Int, newX: Double, newY: Double)
    case deleteWall(wallIndex: Int)
    case addLabel(text: String, x: Double, y: Double)

    var id: String {
        switch self {
        case .dragWallEndpoint(let wallIndex, let endpointIndex, _, _):
            return "drag-\(wallIndex)-\(endpointIndex)"
        case .deleteWall(let wallIndex):
            return "delete-\(wallIndex)"
        case .addLabel(let text, let x, let y):
            return "label-\(text)-\(x)-\(y)"
        }
    }
}

// MARK: - RoomLabel

/// A text label placed on the floor plan to identify rooms.
struct RoomLabel: Sendable, Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    /// Normalized X coordinate on floor plan (0-1).
    var floorPlanX: Double
    /// Normalized Y coordinate on floor plan (0-1).
    var floorPlanY: Double

    init(id: UUID = UUID(), text: String, floorPlanX: Double, floorPlanY: Double) {
        self.id = id
        self.text = text
        self.floorPlanX = floorPlanX
        self.floorPlanY = floorPlanY
    }
}

// MARK: - ARSurveyViewModel

/// ViewModel for the Phase 2 AR-assisted survey after floor plan generation.
///
/// Manages AR position tracking during the Phase 1 survey workflow,
/// providing a blue pulsing "you are here" dot on the 2D floor plan,
/// auto-placement of measurements at AR position, and fallback to
/// manual tap mode when tracking is lost.
@MainActor
@Observable
final class ARSurveyViewModel {

    // MARK: - Observable State

    /// The underlying survey project.
    var project: SurveyProject

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

    /// The currently inspected measurement point.
    var inspectedPoint: MeasurementPoint?

    /// Whether the visualization picker is shown.
    var showVisualizationPicker = false

    /// Error message for display.
    var errorMessage: String?

    /// Live RSSI value from HUD polling.
    private(set) var liveRSSI: Int?

    /// Live SSID from HUD polling.
    private(set) var liveSSID: String?

    /// Current AR tracking status.
    private(set) var trackingStatus: ARTrackingStatus = .notAvailable

    /// Current AR-derived position on the floor plan (normalized 0-1).
    /// Nil when tracking is lost or not available.
    private(set) var currentPositionOnPlan: (x: Double, y: Double)?

    /// Whether the position dot should be shown (tracking normal + within bounds).
    var showPositionDot: Bool {
        trackingStatus == .normal && currentPositionOnPlan != nil
    }

    /// Whether auto-placement mode is active (tracking is normal).
    var isAutoPlacementMode: Bool {
        trackingStatus == .normal
    }

    /// Tracking status message for the user.
    var trackingMessage: String? {
        switch trackingStatus {
        case .normal:
            return nil
        case .limited(let reason):
            return "Tracking limited: \(reason). Tap to place measurements manually."
        case .notAvailable:
            return "AR tracking unavailable. Tap to place measurements manually."
        }
    }

    /// Whether floor plan editing mode is active.
    var isEditingFloorPlan = false

    /// Room labels placed on the floor plan.
    var roomLabels: [RoomLabel] = []

    /// Label being edited/added (for the add label sheet).
    var pendingLabelText: String = ""
    var pendingLabelPosition: (x: Double, y: Double)?
    var showAddLabelSheet = false

    /// Total measurement point count.
    var pointCount: Int { project.measurementPoints.count }

    /// Whether the heatmap overlay should be shown (3+ points).
    var showHeatmap: Bool { project.measurementPoints.count >= 3 }

    /// Spacing guidance text.
    var spacingGuidance: String {
        if project.measurementPoints.isEmpty {
            if isAutoPlacementMode {
                return "Tap \"Measure Here\" to place a measurement at your current position"
            }
            return "Tap on the floor plan to place your first measurement point"
        } else if project.measurementPoints.count < 3 {
            return "Place at least 3 points to generate a heatmap. Space points 3–5 meters apart."
        } else {
            return "Space measurement points 3–5 meters apart for best coverage"
        }
    }

    /// Available visualization types for iOS.
    let availableVisualizations: [HeatmapVisualization] = [
        .signalStrength,
        .downloadSpeed,
        .latency,
    ]

    // MARK: - Private

    private let measurementEngine: any HeatmapServiceProtocol
    private let fileManager: SurveyFileManager.Type
    private let wifiService: any WiFiInfoServiceProtocol
    private var hudPollingTask: Task<Void, Never>?

    /// Coordinate transform from AR world space to floor plan normalized coordinates.
    let coordinateTransform: ARCoordinateTransform

    /// Reference to AR session manager for position tracking (nil if AR not available).
    private let sessionManager: ARSessionManager?

    /// Task for polling AR camera position.
    private var positionTrackingTask: Task<Void, Never>?

    // MARK: - Init

    init(
        project: SurveyProject,
        coordinateTransform: ARCoordinateTransform,
        sessionManager: ARSessionManager? = nil,
        measurementEngine: any HeatmapServiceProtocol,
        wifiService: any WiFiInfoServiceProtocol = WiFiInfoService(),
        fileManager: SurveyFileManager.Type = SurveyFileManager.self
    ) {
        self.project = project
        self.coordinateTransform = coordinateTransform
        self.sessionManager = sessionManager
        self.measurementEngine = measurementEngine
        self.wifiService = wifiService
        self.fileManager = fileManager

        // Load floor plan image
        if let image = UIImage(data: project.floorPlan.imageData) {
            self.floorPlanImage = image
        }
    }

    // MARK: - AR Position Tracking

    /// Starts AR position tracking at ~10Hz.
    func startPositionTracking() {
        stopPositionTracking()

        #if os(iOS) && !targetEnvironment(simulator)
        positionTrackingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.updateARPosition()
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    break
                }
            }
        }
        #endif
    }

    /// Stops AR position tracking.
    func stopPositionTracking() {
        positionTrackingTask?.cancel()
        positionTrackingTask = nil
    }

    /// Updates the current AR camera position and tracking state.
    private func updateARPosition() {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let sessionManager else {
            trackingStatus = .notAvailable
            currentPositionOnPlan = nil
            return
        }

        guard let frame = sessionManager.arView.session.currentFrame else {
            trackingStatus = .notAvailable
            currentPositionOnPlan = nil
            return
        }

        // Check tracking state
        switch frame.camera.trackingState {
        case .normal:
            trackingStatus = .normal
        case .limited(let reason):
            let reasonText: String
            switch reason {
            case .excessiveMotion:
                reasonText = "Move more slowly"
            case .insufficientFeatures:
                reasonText = "Not enough visual features"
            case .initializing:
                reasonText = "Initializing"
            case .relocalizing:
                reasonText = "Relocalizing"
            @unknown default:
                reasonText = "Unknown"
            }
            trackingStatus = .limited(reason: reasonText)
            currentPositionOnPlan = nil
            return
        case .notAvailable:
            trackingStatus = .notAvailable
            currentPositionOnPlan = nil
            return
        }

        // Extract camera position (X, Z for top-down)
        let cameraTransform = frame.camera.transform
        let arX = cameraTransform.columns.3.x
        let arZ = cameraTransform.columns.3.z

        // Convert to floor plan coordinates
        let floorPlanPos = coordinateTransform.arToFloorPlanFloat(arX: arX, arZ: arZ)

        // Only show if within bounds
        if coordinateTransform.isWithinBounds(arX: Double(arX), arZ: Double(arZ)) {
            currentPositionOnPlan = (x: floorPlanPos.floorPlanX, y: floorPlanPos.floorPlanY)
        } else {
            currentPositionOnPlan = nil
        }
        #endif
    }

    // MARK: - Measure Here (Auto-Placement)

    /// Takes a measurement at the current AR position (auto-placement mode).
    func measureAtCurrentPosition() async {
        guard let position = currentPositionOnPlan else {
            errorMessage = "Cannot determine your position. Move to a tracked area or tap to place manually."
            return
        }

        await takeMeasurement(atNormalizedX: position.x, y: position.y)
    }

    /// Takes a measurement at the given normalized floor plan coordinates.
    func takeMeasurement(atNormalizedX x: Double, y: Double) async {
        guard !isMeasuring else { return }

        isMeasuring = true
        defer { isMeasuring = false }

        let point = await measurementEngine.takeMeasurement(at: x, floorPlanY: y)

        // Check for Wi-Fi disconnect
        if point.ssid == nil, point.rssi <= -100 {
            errorMessage = "Wi-Fi is not connected. Connect to a Wi-Fi network before measuring."
            return
        }

        project.measurementPoints.append(point)
        renderHeatmapOverlay()

        Logger.heatmap.debug(
            "AR measurement at (\(x, format: .fixed(precision: 2)), \(y, format: .fixed(precision: 2))), RSSI: \(point.rssi)"
        )
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

    /// Starts polling at 1Hz for live RSSI updates.
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

    // MARK: - Floor Plan Editing

    /// Deletes a wall segment from the floor plan by index.
    func deleteWall(at index: Int) {
        guard var walls = project.floorPlan.walls, index < walls.count else { return }
        walls.remove(at: index)
        project.floorPlan.walls = walls.isEmpty ? nil : walls
    }

    /// Moves a wall endpoint to a new position (real-world meters).
    func moveWallEndpoint(wallIndex: Int, endpointIndex: Int, newX: Double, newY: Double) {
        guard var walls = project.floorPlan.walls, wallIndex < walls.count else { return }

        let wall = walls[wallIndex]
        let updated: WallSegment
        if endpointIndex == 0 {
            updated = WallSegment(
                startX: newX,
                startY: newY,
                endX: wall.endX,
                endY: wall.endY,
                thickness: wall.thickness
            )
        } else {
            updated = WallSegment(
                startX: wall.startX,
                startY: wall.startY,
                endX: newX,
                endY: newY,
                thickness: wall.thickness
            )
        }
        walls[wallIndex] = updated
        project.floorPlan.walls = walls
    }

    /// Adds a room label to the floor plan.
    func addRoomLabel(text: String, atNormalizedX x: Double, y: Double) {
        let label = RoomLabel(text: text, floorPlanX: x, floorPlanY: y)
        roomLabels.append(label)
    }

    /// Deletes a room label.
    func deleteRoomLabel(_ label: RoomLabel) {
        roomLabels.removeAll { $0.id == label.id }
    }

    // MARK: - Save Project

    /// Saves the project to the app's Documents directory.
    func saveProject() {
        let documentsURL = Foundation.FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let safeName = project.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = safeName.isEmpty ? "Untitled" : safeName
        let bundleURL = documentsURL.appendingPathComponent("\(fileName).netmonsurvey")

        do {
            try fileManager.save(project, to: bundleURL)
            Logger.heatmap.debug("AR survey project saved to \(bundleURL.lastPathComponent)")
        } catch {
            errorMessage = "Failed to save project: \(error.localizedDescription)"
            Logger.heatmap.error("Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Cleanup

    /// Stops all tracking, polling, and cleans up AR resources.
    func cleanup() {
        stopPositionTracking()
        stopHUDPolling()
        sessionManager?.stopSession()
    }

    // MARK: - Summary Statistics

    var averageRSSI: Int? {
        let points = project.measurementPoints
        guard !points.isEmpty else { return nil }
        let total = points.reduce(0) { $0 + $1.rssi }
        return total / points.count
    }

    var minRSSI: Int? {
        project.measurementPoints.map(\.rssi).min()
    }

    var maxRSSI: Int? {
        project.measurementPoints.map(\.rssi).max()
    }
}
