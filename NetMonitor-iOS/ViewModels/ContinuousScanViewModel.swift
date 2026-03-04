import CoreGraphics
import Foundation
import NetMonitorCore
import os
import UIKit

// MARK: - ContinuousScanViewModel

/// ViewModel for the Phase 3 AR Continuous Scan feature.
///
/// Coordinates the concurrent AR session + Wi-Fi capture pipeline,
/// manages the scan lifecycle, and provides observable state for the UI.
/// LiDAR is required — non-LiDAR devices are gated at the dashboard level.
@MainActor
@Observable
final class ContinuousScanViewModel {

    // MARK: - Observable State

    /// Current AR device capability.
    private(set) var deviceCapability: ARDeviceCapability

    /// Whether the scan is actively running.
    private(set) var isScanning = false

    /// Whether the scan is paused.
    private(set) var isPaused = false

    /// Number of raw measurements collected.
    private(set) var rawMeasurementCount = 0

    /// Number of downsampled measurement points.
    private(set) var downsampledPointCount = 0

    /// Current RSSI from the latest measurement.
    private(set) var currentRSSI: Int?

    /// Current SSID from the latest measurement.
    private(set) var currentSSID: String?

    /// Current adaptive polling interval.
    private(set) var currentInterval: TimeInterval = ContinuousCapturePipeline.defaultInterval

    /// Whether the user is stationary.
    private(set) var isStationary = false

    /// The generated SurveyProject after finishing the scan.
    private(set) var completedProject: SurveyProject?

    /// Whether the scan is complete and ready for post-processing.
    private(set) var isScanComplete = false

    /// Error message for display.
    var errorMessage: String?

    /// Camera permission status.
    private(set) var cameraPermission: CameraPermissionStatus

    /// AR session state.
    private(set) var sessionState: ARSessionState = .idle

    /// Coverage percentage estimate (approximate based on grid cells).
    var coveragePercentage: Double {
        // Estimate: each grid cell is ~0.5m², assume typical room is ~25m²
        // This is a rough estimate; real value would need the floor plan area
        let estimatedAreaM2 = 25.0
        let cellAreaM2 = Double(ContinuousCapturePipeline.gridCellSize
            * ContinuousCapturePipeline.gridCellSize)
        let coveredCells = Double(downsampledPointCount)
        let totalCells = estimatedAreaM2 / cellAreaM2
        return min(1.0, coveredCells / max(1.0, totalCells))
    }

    /// Whether the device supports LiDAR (required for Phase 3).
    var isLiDARAvailable: Bool {
        deviceCapability == .lidar
    }

    // MARK: - Private

    private let sessionManager: ARSessionManager
    private let pipeline: ContinuousCapturePipeline
    private let wifiService: any WiFiInfoServiceProtocol
    private var statusPollingTask: Task<Void, Never>?

    // MARK: - Init

    init(
        sessionManager: ARSessionManager? = nil,
        measurementEngine: (any HeatmapServiceProtocol)? = nil,
        wifiService: (any WiFiInfoServiceProtocol)? = nil
    ) {
        let manager = sessionManager ?? ARSessionManager()
        self.sessionManager = manager
        self.deviceCapability = manager.deviceCapability
        self.cameraPermission = ARSessionManager.cameraAuthorizationStatus()

        self.wifiService = wifiService ?? WiFiInfoService()

        if let engine = measurementEngine {
            self.pipeline = ContinuousCapturePipeline(measurementEngine: engine)
        } else {
            // Create a dedicated WiFiInfoService for the engine to avoid
            // sending a MainActor-isolated reference across actor boundaries.
            let engineWifi = WiFiInfoService()
            let engine = WiFiMeasurementEngine(
                wifiService: engineWifi,
                speedTestService: NoOpSpeedTestService(),
                pingService: NoOpPingService()
            )
            self.pipeline = ContinuousCapturePipeline(measurementEngine: engine)
        }

        manager.onStateChange = { [weak self] state in
            self?.sessionState = state
        }
    }

    // MARK: - Scan Lifecycle

    /// Starts the continuous scan (AR session + Wi-Fi pipeline).
    func startScan() async {
        guard deviceCapability == .lidar else {
            errorMessage = "Continuous scanning requires a device with LiDAR sensor."
            return
        }

        // Check camera permission
        let permission = ARSessionManager.cameraAuthorizationStatus()
        cameraPermission = permission

        switch permission {
        case .authorized:
            break
        case .notDetermined:
            let result = await sessionManager.requestCameraPermission()
            cameraPermission = result
            if result != .authorized {
                errorMessage = "Camera access is required for AR scanning. Please enable it in Settings."
                return
            }
        case .denied, .restricted:
            errorMessage = "Camera access is required for AR scanning. Please enable it in Settings."
            return
        }

        // Start AR session with meshWithClassification
        sessionManager.startSession()

        // Configure pipeline with position provider
        await pipeline.setPositionProvider { [weak self] in
            await self?.getCurrentARPosition()
        }

        // Start the capture pipeline
        await pipeline.start()
        isScanning = true
        isPaused = false

        // Start status polling
        startStatusPolling()

        Logger.heatmap.info("Continuous scan started")
    }

    /// Pauses the scan — stops AR tracking and Wi-Fi measurement.
    func pauseScan() async {
        sessionManager.pauseSession()
        await pipeline.stop()
        isPaused = true
        stopStatusPolling()

        Logger.heatmap.info("Continuous scan paused")
    }

    /// Resumes the scan after a pause.
    func resumeScan() async {
        sessionManager.startSession()

        await pipeline.setPositionProvider { [weak self] in
            await self?.getCurrentARPosition()
        }
        await pipeline.start()
        isPaused = false

        startStatusPolling()

        Logger.heatmap.info("Continuous scan resumed")
    }

    /// Finishes the scan and creates a SurveyProject with the collected data.
    func finishScan() async {
        // Stop everything
        await pipeline.stop()
        stopStatusPolling()
        isScanning = false
        isPaused = false

        // Get the downsampled measurements
        let points = await pipeline.getDownsampledPoints()

        // Create a minimal floor plan placeholder (the Metal rendering feature
        // will provide the real floor plan from mesh data)
        let placeholderImageData = createPlaceholderFloorPlan()

        let floorPlan = FloorPlan(
            imageData: placeholderImageData,
            widthMeters: 10.0,
            heightMeters: 10.0,
            pixelWidth: 512,
            pixelHeight: 512,
            origin: .arGenerated
        )

        let project = SurveyProject(
            name: "Continuous Scan",
            floorPlan: floorPlan,
            measurementPoints: points,
            surveyMode: .arContinuous
        )

        completedProject = project
        isScanComplete = true

        // Stop AR session
        sessionManager.stopSession()

        Logger.heatmap.info("Continuous scan finished with \(points.count) downsampled points")
    }

    /// Stops the scan without saving (cancel).
    func cancelScan() async {
        await pipeline.reset()
        stopStatusPolling()
        sessionManager.stopSession()
        isScanning = false
        isPaused = false
        rawMeasurementCount = 0
        downsampledPointCount = 0

        Logger.heatmap.info("Continuous scan cancelled")
    }

    /// Cleans up all resources.
    func cleanup() async {
        await pipeline.stop()
        stopStatusPolling()
        sessionManager.stopSession()
    }

    /// Provides the ARSessionManager for the UIViewRepresentable wrapper.
    var arSessionManagerForView: ARSessionManager {
        sessionManager
    }

    // MARK: - AR Position Reading

    /// Gets the current AR camera position (X, Z) or nil if tracking is unavailable.
    /// Called from the capture pipeline at Wi-Fi poll time.
    nonisolated private func getCurrentARPosition() async -> (x: Float, z: Float)? {
        await MainActor.run {
            #if os(iOS) && !targetEnvironment(simulator)
            guard let frame = sessionManager.arView.session.currentFrame else {
                return nil
            }

            // Only return position if tracking is normal
            guard case .normal = frame.camera.trackingState else {
                return nil
            }

            let transform = frame.camera.transform
            return (x: transform.columns.3.x, z: transform.columns.3.z)
            #else
            return nil
            #endif
        }
    }

    // MARK: - Status Polling

    /// Polls the pipeline for UI state updates at ~5Hz.
    private func startStatusPolling() {
        stopStatusPolling()

        statusPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.updateStatus()
                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    break
                }
            }
        }
    }

    private func stopStatusPolling() {
        statusPollingTask?.cancel()
        statusPollingTask = nil
    }

    /// Updates observable state from the pipeline.
    private func updateStatus() async {
        rawMeasurementCount = await pipeline.rawMeasurementCount
        downsampledPointCount = await pipeline.downsampledPointCount
        currentInterval = await pipeline.currentInterval()

        let state = await pipeline.motionState
        switch state {
        case .stationary(let duration):
            isStationary = duration >= ContinuousCapturePipeline.stationaryThreshold
        case .moving:
            isStationary = false
        }

        // Get latest measurement RSSI
        if let lastRaw = await pipeline.rawMeasurements.last {
            currentRSSI = lastRaw.measurement.rssi
            currentSSID = lastRaw.measurement.ssid
        }
    }

    // MARK: - Placeholder Floor Plan

    /// Creates a simple placeholder floor plan image (grey background).
    private func createPlaceholderFloorPlan() -> Data {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }
}
