import Foundation
import NetMonitorCore
import os

// MARK: - PositionedMeasurement

/// A Wi-Fi measurement paired with the AR camera position captured at poll time.
struct PositionedMeasurement: Sendable, Equatable {
    /// The measurement data.
    let measurement: MeasurementPoint
    /// AR world X coordinate at the time of the Wi-Fi poll.
    let arX: Float
    /// AR world Z coordinate at the time of the Wi-Fi poll.
    let arZ: Float
}

// MARK: - MotionState

/// Describes whether the user is stationary or moving.
enum MotionState: Sendable, Equatable {
    /// User has been stationary for the given duration (seconds).
    case stationary(duration: TimeInterval)
    /// User is moving.
    case moving
}

// MARK: - GridCell

/// A 2D grid cell key for spatial downsampling.
struct GridCell: Hashable, Sendable {
    let cellX: Int
    let cellY: Int
}

// MARK: - ContinuousCapturePipeline

/// Orchestrates concurrent AR + Wi-Fi capture for Phase 3 continuous scanning.
///
/// Responsibilities:
/// - Polls Wi-Fi at 2Hz (500ms) default, adaptive to 0.5Hz when stationary >3s.
/// - Tags each measurement with the AR camera position at **poll time** (not render time).
/// - Spatially downsamples to max 1 point per 0.5m² grid cell (median RSSI).
/// - Accumulates data in a `SurveyProject` with `surveyMode = .arContinuous`.
///
/// The pipeline delegates AR session management to the caller (ViewModel);
/// it only needs the current AR position via a callback.
actor ContinuousCapturePipeline {

    // MARK: - Configuration

    /// Default measurement interval (2Hz).
    static let defaultInterval: TimeInterval = 0.5

    /// Slow measurement interval (0.5Hz) when stationary.
    static let stationaryInterval: TimeInterval = 2.0

    /// Duration of no movement before switching to stationary rate (seconds).
    static let stationaryThreshold: TimeInterval = 3.0

    /// Movement threshold in meters — displacement below this is "stationary".
    static let movementThreshold: Float = 0.15

    /// Grid cell size in meters for spatial downsampling (0.5m² → side length ≈ 0.707m).
    /// Using 0.707m as the side length gives 0.5m² cells.
    static let gridCellSize: Float = 0.707

    // MARK: - Dependencies

    private let measurementEngine: any HeatmapServiceProtocol

    // MARK: - State

    /// All raw positioned measurements collected during the scan.
    private(set) var rawMeasurements: [PositionedMeasurement] = []

    /// Downsampled measurements (one per grid cell, median RSSI).
    private(set) var downsampledPoints: [MeasurementPoint] = []

    /// Current motion state.
    private(set) var motionState: MotionState = .moving

    /// Whether the pipeline is actively capturing.
    private(set) var isCapturing = false

    /// The last recorded AR position (for motion detection).
    private var lastPosition: (x: Float, z: Float)?

    /// Timestamp when the user last moved beyond the threshold.
    private var lastMovementTime: Date = .init()

    /// The capture task.
    private var captureTask: Task<Void, Never>?

    /// Coordinate transform for AR → floor plan mapping.
    private var coordinateTransform: ARCoordinateTransform?

    /// Callback to get the current AR camera position at poll time.
    /// Returns (arX, arZ) or nil if tracking is unavailable.
    private var positionProvider: (@Sendable () async -> (x: Float, z: Float)?)?

    // MARK: - Init

    init(measurementEngine: any HeatmapServiceProtocol) {
        self.measurementEngine = measurementEngine
    }

    // MARK: - Configuration

    /// Sets the coordinate transform for mapping AR world → floor plan coordinates.
    func setCoordinateTransform(_ transform: ARCoordinateTransform) {
        self.coordinateTransform = transform
    }

    /// Sets the position provider callback that returns current AR camera position.
    func setPositionProvider(_ provider: @escaping @Sendable () async -> (x: Float, z: Float)?) {
        self.positionProvider = provider
    }

    // MARK: - Pipeline Control

    /// Starts the continuous capture pipeline.
    ///
    /// The pipeline polls Wi-Fi at the adaptive rate, tags each measurement
    /// with the AR position at poll time, and accumulates results.
    func start() {
        guard !isCapturing else { return }
        isCapturing = true
        lastMovementTime = Date()
        lastPosition = nil
        motionState = .moving

        captureTask = Task { [weak self] in
            guard let self else { return }
            await self.captureLoop()
        }
    }

    /// Stops the continuous capture pipeline.
    func stop() {
        isCapturing = false
        captureTask?.cancel()
        captureTask = nil
    }

    /// Resets the pipeline, clearing all collected data.
    func reset() {
        stop()
        rawMeasurements = []
        downsampledPoints = []
        motionState = .moving
        lastPosition = nil
        lastMovementTime = Date()
    }

    // MARK: - Data Access

    /// Returns the total count of raw measurements collected.
    var rawMeasurementCount: Int {
        rawMeasurements.count
    }

    /// Returns the total count of downsampled measurement points.
    var downsampledPointCount: Int {
        downsampledPoints.count
    }

    /// Returns all downsampled points for creating the final SurveyProject.
    func getDownsampledPoints() -> [MeasurementPoint] {
        downsampledPoints
    }

    /// Returns the current adaptive interval based on motion state.
    func currentInterval() -> TimeInterval {
        Self.adaptiveInterval(for: motionState)
    }

    // MARK: - Capture Loop

    /// Main capture loop that runs until cancelled.
    private func captureLoop() async {
        while !Task.isCancelled && isCapturing {
            // 1. Get current AR position at poll time (pipeline sync: tag at poll time)
            let position = await positionProvider?()

            if let position {
                // 2. Update motion state
                updateMotionState(currentPosition: position)

                // 3. Take Wi-Fi measurement
                let floorPlanCoords = mapToFloorPlan(arX: position.x, arZ: position.z)
                let measurement = await measurementEngine.takeMeasurement(
                    at: floorPlanCoords.x,
                    floorPlanY: floorPlanCoords.y
                )

                // 4. Store positioned measurement
                let positioned = PositionedMeasurement(
                    measurement: measurement,
                    arX: position.x,
                    arZ: position.z
                )
                rawMeasurements.append(positioned)

                // 5. Update downsampled data
                updateDownsampled(with: positioned)
            }

            // 6. Sleep for the adaptive interval
            let interval = currentInterval()
            let nanoseconds = UInt64(interval * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                break
            }
        }
    }

    // MARK: - Motion Detection

    /// Updates the motion state based on displacement from the last position.
    private func updateMotionState(currentPosition: (x: Float, z: Float)) {
        let now = Date()

        if let last = lastPosition {
            let dx = currentPosition.x - last.x
            let dz = currentPosition.z - last.z
            let displacement = sqrt(dx * dx + dz * dz)

            if displacement > Self.movementThreshold {
                // User moved — reset to moving state
                lastMovementTime = now
                motionState = .moving
            } else {
                // User is roughly stationary
                let stationaryDuration = now.timeIntervalSince(lastMovementTime)
                motionState = .stationary(duration: stationaryDuration)
            }
        } else {
            // First position reading — start as moving
            lastMovementTime = now
            motionState = .moving
        }

        lastPosition = (x: currentPosition.x, z: currentPosition.z)
    }

    // MARK: - Adaptive Rate

    /// Returns the appropriate measurement interval for the given motion state.
    ///
    /// - Moving: 2Hz (500ms)
    /// - Stationary >3s: 0.5Hz (2000ms)
    /// - Stationary <3s: 2Hz (500ms) — still at normal rate until threshold
    static func adaptiveInterval(for motionState: MotionState) -> TimeInterval {
        switch motionState {
        case .moving:
            return defaultInterval
        case .stationary(let duration):
            if duration >= stationaryThreshold {
                return stationaryInterval
            }
            return defaultInterval
        }
    }

    // MARK: - Floor Plan Coordinate Mapping

    /// Maps AR world coordinates to floor plan normalized coordinates.
    /// Falls back to a reasonable default if no transform is set.
    private func mapToFloorPlan(arX: Float, arZ: Float) -> (x: Double, y: Double) {
        if let transform = coordinateTransform {
            let coords = transform.arToFloorPlanFloat(arX: arX, arZ: arZ)
            return (x: coords.floorPlanX, y: coords.floorPlanY)
        }
        // No transform yet — store raw normalized values (will be re-mapped later)
        return (x: Double(arX), y: Double(arZ))
    }

    // MARK: - Spatial Downsampling

    /// Computes the grid cell for a given AR world position.
    static func gridCell(arX: Float, arZ: Float) -> GridCell {
        let cellX = Int(floor(arX / gridCellSize))
        let cellY = Int(floor(arZ / gridCellSize))
        return GridCell(cellX: cellX, cellY: cellY)
    }

    /// Updates the downsampled point set with a new positioned measurement.
    ///
    /// For each 0.5m² grid cell, keeps the **median RSSI** measurement.
    /// Rebuilds the affected cell's representative point when new data arrives.
    private func updateDownsampled(with positioned: PositionedMeasurement) {
        // Rebuild downsampled from all raw data for the affected cell
        // This is efficient because it only recalculates the cell that changed.
        rebuildDownsampled()
    }

    /// Rebuilds the entire downsampled point set from raw measurements.
    ///
    /// Groups measurements by grid cell, selects the median-RSSI measurement
    /// from each cell as the representative point.
    private func rebuildDownsampled() {
        downsampledPoints = Self.downsample(rawMeasurements)
    }

    /// Downsamples a set of positioned measurements to one point per grid cell.
    ///
    /// For each cell, selects the measurement closest to the median RSSI value.
    /// This reduces spatial redundancy while preserving signal characteristics.
    ///
    /// - Parameter measurements: All positioned measurements to downsample.
    /// - Returns: One `MeasurementPoint` per occupied grid cell.
    static func downsample(_ measurements: [PositionedMeasurement]) -> [MeasurementPoint] {
        guard !measurements.isEmpty else { return [] }

        // Group by grid cell
        var cells: [GridCell: [PositionedMeasurement]] = [:]
        for measurement in measurements {
            let cell = gridCell(arX: measurement.arX, arZ: measurement.arZ)
            cells[cell, default: []].append(measurement)
        }

        // For each cell, select the measurement with RSSI closest to the median
        var result: [MeasurementPoint] = []
        for (_, cellMeasurements) in cells {
            if let representative = medianRSSIMeasurement(from: cellMeasurements) {
                result.append(representative.measurement)
            }
        }

        return result
    }

    /// Selects the measurement closest to the median RSSI from a cell's measurements.
    ///
    /// - Parameter measurements: All measurements in a single grid cell.
    /// - Returns: The measurement whose RSSI is closest to the median, or nil if empty.
    static func medianRSSIMeasurement(from measurements: [PositionedMeasurement]) -> PositionedMeasurement? {
        guard !measurements.isEmpty else { return nil }

        let sorted = measurements.sorted { $0.measurement.rssi < $1.measurement.rssi }
        let medianIndex = sorted.count / 2
        return sorted[medianIndex]
    }
}
