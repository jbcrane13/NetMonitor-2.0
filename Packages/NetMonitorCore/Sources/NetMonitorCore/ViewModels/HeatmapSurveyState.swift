import CoreGraphics
import Foundation

// MARK: - HeatmapSurveyState

/// Cross-platform state-machine for Wi-Fi heatmap surveys.
///
/// Owns every piece of state that was previously duplicated between
/// `HeatmapSurveyViewModel` (iOS) and `WiFiHeatmapViewModel` (macOS):
/// the survey project, measurement points, calibration, visualization
/// settings, undo stack, and AP filter. Platform VMs hold an instance and
/// add only their acquisition-layer integration (Shortcuts companion on iOS,
/// CoreWLAN on macOS) plus persistence + rendering deltas.
///
/// Originally framed by the arch-review consensus (#202) as a "pure value
/// type". Implemented here as `@MainActor @Observable final class` because
/// SwiftUI's Observation framework only tracks stored property access on
/// reference types — a value-type struct would not trigger view redraws on
/// field mutations.
@MainActor
@Observable
public final class HeatmapSurveyState {

    // MARK: - Survey

    public var surveyProject: SurveyProject?
    public private(set) var measurementPoints: [MeasurementPoint] = []
    public var isSurveying: Bool = false
    public var errorMessage: String?

    // MARK: - Measurement Mode

    public var isMeasuring: Bool = false
    public var pendingMeasurementLocation: CGPoint?

    // MARK: - Calibration

    public var isCalibrating: Bool = false
    public var isCalibrated: Bool = false
    public private(set) var calibrationPoints: [CalibrationPoint] = []
    public var calibrationDistance: Double = 5.0
    public var showCalibrationSheet: Bool = false

    // MARK: - Visualization

    public var selectedVisualization: HeatmapVisualization = .signalStrength
    public var selectedColorScheme: HeatmapColorScheme = .thermal
    public var heatmapOpacity: Double = 0.7
    public var selectedAPFilter: String?

    // MARK: - Undo

    private var undoStack: [[MeasurementPoint]] = []
    /// Maximum number of undo snapshots kept. Older entries are dropped
    /// FIFO once exceeded.
    public static let maxUndoSnapshots = 50

    public var canUndo: Bool { !undoStack.isEmpty }

    // MARK: - Init

    public init() {}

    // MARK: - Computed

    public var hasFloorPlan: Bool { surveyProject != nil }

    public var filteredPoints: [MeasurementPoint] {
        guard let bssid = selectedAPFilter else { return measurementPoints }
        return measurementPoints.filter { $0.bssid == bssid }
    }

    public var uniqueBSSIDs: [(bssid: String, ssid: String)] {
        let groups = Dictionary(grouping: measurementPoints, by: { $0.bssid ?? "unknown" })
        return groups
            .compactMap { bssid, points -> (bssid: String, ssid: String)? in
                guard bssid != "unknown" else { return nil }
                let ssid = points.first?.ssid ?? bssid
                return (bssid: bssid, ssid: ssid)
            }
            .sorted { $0.ssid < $1.ssid }
    }

    public var averageRSSI: Double? {
        let pts = filteredPoints
        guard !pts.isEmpty else { return nil }
        return Double(pts.reduce(0) { $0 + $1.rssi }) / Double(pts.count)
    }

    public var minRSSI: Int? { filteredPoints.map(\.rssi).min() }
    public var maxRSSI: Int? { filteredPoints.map(\.rssi).max() }

    // MARK: - Survey Lifecycle

    public func startSurvey() {
        guard surveyProject != nil, isCalibrated else { return }
        isSurveying = true
    }

    public func stopSurvey() {
        isSurveying = false
    }

    // MARK: - Calibration

    public func startCalibration() {
        isCalibrating = true
        isCalibrated = false
        calibrationPoints = []
    }

    public func cancelCalibration() {
        isCalibrating = false
        calibrationPoints = []
    }

    public func skipCalibration() {
        isCalibrating = false
        isCalibrated = true
        calibrationPoints = []
    }

    /// Adds a calibration tap. Triggers `showCalibrationSheet` once two
    /// points are recorded so the UI can prompt for the real-world distance.
    public func addCalibrationPoint(at normalizedPoint: CGPoint) {
        guard calibrationPoints.count < 2 else { return }
        calibrationPoints.append(
            CalibrationPoint(pixelX: Double(normalizedPoint.x), pixelY: Double(normalizedPoint.y))
        )
        if calibrationPoints.count == 2 {
            showCalibrationSheet = true
        }
    }

    /// Completes calibration using a distance value supplied by the user,
    /// recomputing the floor-plan's `widthMeters`/`heightMeters` from the
    /// captured pixel-distance ratio. Resets calibration state on success.
    /// No-op if fewer than two calibration points are recorded or no
    /// `surveyProject` exists.
    public func completeCalibration(withDistance distanceMeters: Double) {
        guard calibrationPoints.count == 2, var project = surveyProject else {
            calibrationPoints = []
            isCalibrating = false
            showCalibrationSheet = false
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

    /// Converts a distance supplied in feet (when `isFeet` is true) to
    /// meters and forwards to ``completeCalibration(withDistance:)``.
    public func completeCalibration(distance: Double, isFeet: Bool) {
        let realDistance = isFeet ? distance * 0.3048 : distance
        completeCalibration(withDistance: realDistance)
    }

    // MARK: - Measurements

    /// Appends a freshly-acquired measurement to the survey. Captures an
    /// undo snapshot of the prior point list so a subsequent ``undo()``
    /// restores the state before this append.
    public func recordMeasurement(_ point: MeasurementPoint) {
        saveUndoState()
        measurementPoints.append(point)
    }

    /// Removes the measurement with the given id and snapshots prior state.
    public func deleteMeasurement(id: UUID) {
        saveUndoState()
        measurementPoints.removeAll { $0.id == id }
    }

    /// Replaces the entire measurement list. Useful when restoring from
    /// persistence; does not snapshot undo (consumers can call
    /// `clearUndo()` if needed).
    public func setMeasurements(_ points: [MeasurementPoint]) {
        measurementPoints = points
    }

    public func clearMeasurements() {
        saveUndoState()
        measurementPoints = []
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        measurementPoints = previous
    }

    /// Wipes the undo history. Called after loading a new project so the
    /// undo stack doesn't allow rolling into the previous project's points.
    public func clearUndo() {
        undoStack = []
    }

    private func saveUndoState() {
        undoStack.append(measurementPoints)
        if undoStack.count > Self.maxUndoSnapshots {
            undoStack.removeFirst()
        }
    }

    // MARK: - Project Lifecycle

    /// Replaces the active project, clearing measurement-related state.
    /// Calibration is reset (`isCalibrating = true`, `isCalibrated = false`)
    /// unless the floor plan already has calibration points recorded — in
    /// that case the project is treated as pre-calibrated (RoomPlan
    /// blueprints, loaded saved projects).
    public func setProject(_ project: SurveyProject) {
        surveyProject = project
        measurementPoints = project.measurementPoints
        calibrationPoints = []
        clearUndo()
        let preCalibrated = project.floorPlan.calibrationPoints?.isEmpty == false
        isCalibrated = preCalibrated
        isCalibrating = !preCalibrated
    }
}
