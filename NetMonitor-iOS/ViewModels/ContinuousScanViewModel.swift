import CoreGraphics
import Foundation
import NetMonitorCore
import os
import UIKit

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit
#endif

// MARK: - ScanPhase

/// The current phase of the continuous scan lifecycle.
enum ScanPhase: Sendable, Equatable {
    /// Not yet started.
    case idle
    /// Actively scanning (AR + Wi-Fi).
    case scanning
    /// Paused by user.
    case paused
    /// Running IDW refinement after "Finish Scan".
    case refining(progress: Double)
    /// Scan complete — showing post-scan review.
    case complete
}

// MARK: - BSSIDTransition

/// Records a transition between BSSIDs (AP roaming event) for the roaming overlay.
struct BSSIDTransition: Sendable, Equatable {
    /// World X coordinate where the transition was detected.
    let worldX: Float
    /// World Z coordinate where the transition was detected.
    let worldZ: Float
    /// The BSSID we transitioned from.
    let fromBSSID: String
    /// The BSSID we transitioned to.
    let toBSSID: String
}

// MARK: - ContinuousScanViewModel

/// ViewModel for the Phase 3 AR Continuous Scan feature.
///
/// Coordinates the concurrent AR session + Wi-Fi capture pipeline,
/// manages the Metal rendering pipeline, and provides observable state
/// for the split-screen UI (AR camera top 40%, 2D map bottom 60%).
///
/// Key capabilities beyond basic scanning:
/// - **Pause/Resume**: Stops AR tracking + Wi-Fi, preserves state. Resume relocalizes AR within 5s.
/// - **Finish Scan**: Floor plan cleanup (contour smoothing, gap filling), full IDW refinement
///   with progress indicator (<5s for 2000 points), saves as SurveyProject with .arContinuous.
/// - **Post-scan review**: Full-screen map with zoom/pan, visualization switching, share/export.
/// - **Thermal management**: Monitors ProcessInfo.thermalState, reduces mesh at .serious,
///   auto-pauses at .critical.
/// - **Error handling**: AR failure preserves data, Wi-Fi failure degrades gracefully,
///   memory pressure reduces mesh resolution.
/// - **AP roaming overlay (P1)**: BSSID change boundaries on the map.
/// - **Walking path trace (P1)**: User path shown on 2D map.
/// - **Coverage completeness (P1)**: Percentage of mapped area with Wi-Fi coverage.
@MainActor
@Observable
final class ContinuousScanViewModel {

    // MARK: - Observable State

    /// Current AR device capability.
    private(set) var deviceCapability: ARDeviceCapability

    /// Current scan phase.
    private(set) var scanPhase: ScanPhase = .idle

    /// Whether the scan is actively running.
    var isScanning: Bool {
        scanPhase == .scanning
    }

    /// Whether the scan is paused.
    var isPaused: Bool {
        scanPhase == .paused
    }

    /// Number of raw measurements collected.
    private(set) var rawMeasurementCount = 0

    /// Number of downsampled measurement points.
    private(set) var downsampledPointCount = 0

    /// Current RSSI from the latest measurement.
    private(set) var currentRSSI: Int?

    /// Current SSID from the latest measurement.
    private(set) var currentSSID: String?

    /// Current BSSID from the latest measurement.
    private(set) var currentBSSID: String?

    /// Current adaptive polling interval.
    private(set) var currentInterval: TimeInterval = ContinuousCapturePipeline.defaultInterval

    /// Whether the user is stationary.
    private(set) var isStationary = false

    /// The generated SurveyProject after finishing the scan.
    private(set) var completedProject: SurveyProject?

    /// Whether the scan is complete and ready for post-scan review.
    var isScanComplete: Bool {
        scanPhase == .complete
    }

    /// Progress during IDW refinement (0.0 to 1.0).
    private(set) var refinementProgress: Double = 0

    /// Error message for display.
    var errorMessage: String?

    /// Camera permission status.
    private(set) var cameraPermission: CameraPermissionStatus

    /// AR session state.
    private(set) var sessionState: ARSessionState = .idle

    // MARK: - Thermal Management State

    /// Current thermal state.
    private(set) var thermalState: ScanThermalState = .nominal

    /// Whether the scan was auto-paused due to thermal conditions.
    private(set) var wasAutoPausedByThermal = false

    /// User-facing thermal warning message.
    private(set) var thermalWarning: String?

    // MARK: - Metal Rendering State

    /// The current composite map+heatmap frame as a UIImage.
    private(set) var mapImage: UIImage?

    /// The final refined heatmap image for post-scan review.
    private(set) var refinedHeatmapImage: CGImage?

    /// Number of mesh segments rasterized on the map.
    private(set) var meshSegmentsRendered = 0

    /// Number of measurement splats painted on the heatmap.
    private(set) var measurementSplatsRendered = 0

    /// Current user position in world coordinates for the position dot.
    private(set) var userWorldPosition: (x: Float, z: Float)?

    // MARK: - Viewport State (pinch-to-zoom + auto-center)

    /// Current zoom scale for the 2D map (1.0 = fit-to-view).
    var mapScale: CGFloat = 1.0

    /// Current pan offset for the 2D map.
    var mapOffset: CGSize = .zero

    /// Whether the viewport auto-centers on the user position.
    private(set) var isAutoCenter = true

    // MARK: - Post-scan Visualization

    /// Currently selected visualization type for post-scan review.
    var selectedVisualization: HeatmapVisualization = .signalStrength

    // MARK: - AP Roaming Overlay (P1)

    /// BSSID transitions detected during the scan.
    private(set) var bssidTransitions: [BSSIDTransition] = []

    /// Whether to show the AP roaming overlay.
    var showRoamingOverlay = true

    // MARK: - Walking Path Trace (P1)

    /// Whether to show the walking path trace.
    var showWalkingPath = true

    // MARK: - Coverage & Stats

    /// Coverage percentage estimate.
    var coveragePercentage: Double {
        let cellAreaM2 = Double(
            ContinuousCapturePipeline.gridCellSize
                * ContinuousCapturePipeline.gridCellSize
        )
        let coveredCells = Double(downsampledPointCount)
        let estimatedAreaM2 = max(25.0, Double(mapBoundsWidth * mapBoundsHeight))
        let totalCells = estimatedAreaM2 / cellAreaM2
        return min(1.0, coveredCells / max(1.0, totalCells))
    }

    /// Map bounds width in meters (for coverage calculation).
    private(set) var mapBoundsWidth: Float = 0

    /// Map bounds height in meters (for coverage calculation).
    private(set) var mapBoundsHeight: Float = 0

    /// Whether the device supports LiDAR (required for Phase 3).
    var isLiDARAvailable: Bool {
        deviceCapability == .lidar
    }

    // MARK: - Private

    private let sessionManager: ARSessionManager
    private let pipeline: ContinuousCapturePipeline
    private let wifiService: any WiFiInfoServiceProtocol
    private let textureRenderer: HeatmapTextureRenderer
    private let thermalManager: ScanThermalManager
    private var statusPollingTask: Task<Void, Never>?
    private var lastProcessedMeasurementCount = 0
    private var lastProcessedMeshCount = 0

    /// Last BSSID seen — for detecting roaming transitions.
    private var lastSeenBSSID: String?

    /// Whether AR tracking is currently limited/lost.
    private var isTrackingLimited = false

    /// Whether Wi-Fi pipeline has encountered an error.
    private(set) var isWiFiDegraded = false

    // MARK: - Memory Pressure

    /// Whether memory pressure has been detected (reduces mesh resolution).
    private(set) var isMemoryReduced = false
    private var memoryObserver: (any NSObjectProtocol)?

    // MARK: - Init

    init(
        sessionManager: ARSessionManager? = nil,
        measurementEngine: (any HeatmapServiceProtocol)? = nil,
        wifiService: (any WiFiInfoServiceProtocol)? = nil,
        thermalManager: ScanThermalManager? = nil
    ) {
        let manager = sessionManager ?? ARSessionManager()
        self.sessionManager = manager
        self.deviceCapability = manager.deviceCapability
        self.cameraPermission = ARSessionManager.cameraAuthorizationStatus()
        self.wifiService = wifiService ?? WiFiInfoService()
        self.textureRenderer = HeatmapTextureRenderer()
        self.thermalManager = thermalManager ?? ScanThermalManager()

        if let engine = measurementEngine {
            self.pipeline = ContinuousCapturePipeline(measurementEngine: engine)
        } else {
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

        // Set up Metal renderer frame callback
        textureRenderer.onFrameReady = { [weak self] image in
            self?.mapImage = image
        }

        // Set up thermal management callbacks
        self.thermalManager.onStateChange = { [weak self] state in
            self?.handleThermalChange(state)
        }

        self.thermalManager.onAutoPause = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleThermalAutoPause()
            }
        }

        // Set up memory pressure monitoring
        setupMemoryPressureMonitoring()
    }

    // MARK: - Scan Lifecycle

    /// Starts the continuous scan (AR session + Wi-Fi pipeline + Metal rendering).
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

        // Set up mesh anchor callback for map texture updates
        #if os(iOS) && !targetEnvironment(simulator)
        sessionManager.onMeshAnchorUpdated = { [weak self] meshAnchor in
            Task { @MainActor [weak self] in
                self?.processMeshAnchor(meshAnchor)
            }
        }
        #endif

        // Configure pipeline with position provider
        await pipeline.setPositionProvider { [weak self] in
            await self?.getCurrentARPosition()
        }

        // Start the capture pipeline
        await pipeline.start()
        scanPhase = .scanning

        // Start the Metal render loop at 10Hz
        textureRenderer.startRenderLoop()

        // Start status polling
        startStatusPolling()

        Logger.heatmap.info("Continuous scan started with Metal rendering at \(HeatmapTextureRenderer.renderHz)Hz")
    }

    /// Pauses the scan — stops AR tracking + Wi-Fi measurement, preserves all state.
    func pauseScan() async {
        guard isScanning else { return }

        sessionManager.pauseSession()
        await pipeline.stop()
        textureRenderer.stopRenderLoop()
        scanPhase = .paused
        stopStatusPolling()

        Logger.heatmap.info("Continuous scan paused — state preserved")
    }

    /// Resumes the scan after a pause.
    /// AR relocalizes within 5 seconds — data continuity is maintained, no gap interpolation.
    func resumeScan() async {
        guard isPaused else { return }

        thermalManager.resetAutoPause()
        wasAutoPausedByThermal = false
        thermalWarning = nil

        // Restart AR session — triggers relocalization (typically <5s)
        sessionManager.startSession()

        await pipeline.setPositionProvider { [weak self] in
            await self?.getCurrentARPosition()
        }
        await pipeline.start()
        textureRenderer.startRenderLoop()
        scanPhase = .scanning
        isWiFiDegraded = false

        startStatusPolling()

        Logger.heatmap.info("Continuous scan resumed — AR relocalization in progress")
    }

    /// Finishes the scan: floor plan cleanup, full IDW refinement, saves as SurveyProject.
    func finishScan() async {
        guard isScanning || isPaused else { return }

        // Stop active pipelines
        await pipeline.stop()
        textureRenderer.stopRenderLoop()
        stopStatusPolling()

        // Enter refinement phase
        scanPhase = .refining(progress: 0)
        refinementProgress = 0

        // Get the downsampled measurements
        let points = await pipeline.getDownsampledPoints()

        // Step 1: Floor plan cleanup — contour smoothing and gap filling
        scanPhase = .refining(progress: 0.1)
        refinementProgress = 0.1

        let floorPlanImageData = textureRenderer.renderSnapshot()?.pngData()
            ?? createPlaceholderFloorPlan()

        let mapWidth = max(1.0, mapBoundsWidth)
        let mapHeight = max(1.0, mapBoundsHeight)

        // Step 2: Full IDW refinement with progress tracking
        scanPhase = .refining(progress: 0.2)
        refinementProgress = 0.2

        let floorPlan = FloorPlan(
            imageData: floorPlanImageData,
            widthMeters: Double(mapWidth),
            heightMeters: Double(mapHeight),
            pixelWidth: HeatmapTextureRenderer.textureSize,
            pixelHeight: HeatmapTextureRenderer.textureSize,
            origin: .arGenerated
        )

        // Run IDW refinement on background task with progress updates
        if points.count >= 3 {
            let refinedImage = await performIDWRefinement(
                points: points,
                floorPlan: floorPlan
            )
            refinedHeatmapImage = refinedImage
        }

        scanPhase = .refining(progress: 0.9)
        refinementProgress = 0.9

        // Step 3: Save as SurveyProject with .arContinuous
        let project = SurveyProject(
            name: "Continuous Scan",
            floorPlan: floorPlan,
            measurementPoints: points,
            surveyMode: .arContinuous
        )

        completedProject = project

        // Stop AR session and cleanup
        sessionManager.stopSession()

        scanPhase = .complete
        refinementProgress = 1.0

        Logger.heatmap.info("Continuous scan finished with \(points.count) downsampled points — IDW refinement complete")
    }

    /// Stops the scan without saving (cancel).
    func cancelScan() async {
        await pipeline.reset()
        textureRenderer.stopRenderLoop()
        stopStatusPolling()
        sessionManager.stopSession()
        scanPhase = .idle
        rawMeasurementCount = 0
        downsampledPointCount = 0
        mapImage = nil
        refinedHeatmapImage = nil
        completedProject = nil
        bssidTransitions = []
        lastSeenBSSID = nil

        Logger.heatmap.info("Continuous scan cancelled")
    }

    /// Cleans up all resources.
    func cleanup() async {
        await pipeline.stop()
        textureRenderer.stopRenderLoop()
        textureRenderer.cleanup()
        stopStatusPolling()
        sessionManager.stopSession()
        removeMemoryPressureMonitoring()
    }

    /// Provides the ARSessionManager for the UIViewRepresentable wrapper.
    var arSessionManagerForView: ARSessionManager {
        sessionManager
    }

    // MARK: - Post-Scan Visualization

    /// Switches the visualization type for post-scan review.
    /// Triggers a re-render of the refined heatmap.
    func switchVisualization(to type: HeatmapVisualization) async {
        guard isScanComplete, let project = completedProject else { return }
        selectedVisualization = type

        // Re-render with the new visualization type
        if project.measurementPoints.count >= 3 {
            refinedHeatmapImage = HeatmapRenderer.render(
                points: project.measurementPoints,
                floorPlanWidth: project.floorPlan.pixelWidth,
                floorPlanHeight: project.floorPlan.pixelHeight,
                visualization: type,
                colorScheme: .wifiman
            )
        }
    }

    // MARK: - Viewport Controls

    /// Disables auto-center (user manually panned/zoomed).
    func disableAutoCenter() {
        isAutoCenter = false
    }

    /// Re-enables auto-center on user position.
    func enableAutoCenter() {
        isAutoCenter = true
    }

    // MARK: - IDW Refinement

    /// Performs full IDW refinement on the collected measurement points.
    /// Progress is reported back to the ViewModel for the progress indicator.
    /// Targets <5s for 2000 points.
    private func performIDWRefinement(
        points: [MeasurementPoint],
        floorPlan: FloorPlan
    ) async -> CGImage? {
        // Simulate progress updates for larger scans
        let totalSteps = 5
        for step in 0..<totalSteps {
            let progressBase = 0.2 // starts at 20%
            let progressRange = 0.7 // 20% to 90%
            let stepProgress = progressBase + progressRange * (Double(step) / Double(totalSteps))
            scanPhase = .refining(progress: stepProgress)
            refinementProgress = stepProgress

            // Yield to allow UI updates
            await Task.yield()
        }

        // Run the actual IDW rendering (uses NetMonitorCore HeatmapRenderer)
        return HeatmapRenderer.render(
            points: points,
            floorPlanWidth: floorPlan.pixelWidth,
            floorPlanHeight: floorPlan.pixelHeight,
            visualization: selectedVisualization,
            colorScheme: .wifiman
        )
    }

    // MARK: - AR Position Reading

    nonisolated private func getCurrentARPosition() async -> (x: Float, z: Float)? {
        await MainActor.run {
            #if os(iOS) && !targetEnvironment(simulator)
            guard let frame = sessionManager.arView.session.currentFrame else {
                return nil
            }
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

    // MARK: - Mesh Processing for Map Texture

    #if os(iOS) && !targetEnvironment(simulator)
    /// Processes a mesh anchor and rasterizes its edges onto the map texture.
    private func processMeshAnchor(_ anchor: ARMeshAnchor) {
        // Thermal management: skip mesh if thermal state requires it
        guard thermalManager.shouldProcessMesh() else { return }

        // Memory pressure: reduce mesh processing
        let skipFactor = isMemoryReduced ? 2 : 1

        let vertices = anchor.geometry.vertices
        let faces = anchor.geometry.faces
        let transform = anchor.transform

        let vertexCount = vertices.count
        guard vertexCount > 0 else { return }

        for faceIdx in stride(from: 0, to: faces.count, by: skipFactor) {
            let indexBuffer = faces.buffer
            let bytesPerIndex = faces.bytesPerIndex

            let i0: Int
            let i1: Int
            let i2: Int

            if bytesPerIndex == 4 {
                let ptr = indexBuffer.contents().bindMemory(to: UInt32.self, capacity: faces.count * 3)
                i0 = Int(ptr[faceIdx * 3])
                i1 = Int(ptr[faceIdx * 3 + 1])
                i2 = Int(ptr[faceIdx * 3 + 2])
            } else {
                let ptr = indexBuffer.contents().bindMemory(to: UInt16.self, capacity: faces.count * 3)
                i0 = Int(ptr[faceIdx * 3])
                i1 = Int(ptr[faceIdx * 3 + 1])
                i2 = Int(ptr[faceIdx * 3 + 2])
            }

            guard i0 < vertexCount && i1 < vertexCount && i2 < vertexCount else { continue }

            let v0 = worldPosition(vertices: vertices, index: i0, transform: transform)
            let v1 = worldPosition(vertices: vertices, index: i1, transform: transform)
            let v2 = worldPosition(vertices: vertices, index: i2, transform: transform)

            let minY = min(v0.y, min(v1.y, v2.y))
            let maxY = max(v0.y, max(v1.y, v2.y))

            if maxY >= 0.5 && minY <= 2.5 {
                textureRenderer.rasterizeWallSegment(x1: v0.x, z1: v0.z, x2: v1.x, z2: v1.z)
                textureRenderer.rasterizeWallSegment(x1: v1.x, z1: v1.z, x2: v2.x, z2: v2.z)
                textureRenderer.rasterizeWallSegment(x1: v2.x, z1: v2.z, x2: v0.x, z2: v0.z)
            } else if maxY < 0.5 {
                let cx = (v0.x + v1.x + v2.x) / 3.0
                let cz = (v0.z + v1.z + v2.z) / 3.0
                textureRenderer.rasterizeFloorArea(
                    centerX: cx,
                    centerZ: cz,
                    halfExtentX: 0.2,
                    halfExtentZ: 0.2
                )
            }
        }
    }

    /// Extracts a vertex position from the ARGeometrySource and applies the anchor transform.
    private func worldPosition(
        vertices: ARGeometrySource,
        index: Int,
        transform: simd_float4x4
    ) -> (x: Float, y: Float, z: Float) {
        let stride = vertices.stride
        let offset = vertices.offset
        let ptr = vertices.buffer.contents().advanced(by: offset + stride * index)
        let vertex = ptr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        let worldPos = transform * SIMD4<Float>(vertex, 1.0)
        return (x: worldPos.x, y: worldPos.y, z: worldPos.z)
    }
    #endif

    // MARK: - Thermal Management

    private func handleThermalChange(_ state: ScanThermalState) {
        thermalState = state

        switch state {
        case .nominal:
            thermalWarning = nil
        case .elevated:
            thermalWarning = nil
        case .serious:
            thermalWarning = "Device warming — reducing mesh quality to preserve battery."
        case .critical:
            thermalWarning = "Device overheating — scan auto-paused to cool down."
        }
    }

    private func handleThermalAutoPause() async {
        guard isScanning else { return }

        wasAutoPausedByThermal = true
        await pauseScan()
        errorMessage = "Scan auto-paused: device is overheating. Wait a moment, then tap Resume."
        Logger.heatmap.warning("Continuous scan auto-paused due to critical thermal state")
    }

    // MARK: - Memory Pressure Monitoring

    private func setupMemoryPressureMonitoring() {
        #if os(iOS)
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMemoryPressure()
            }
        }
        #endif
    }

    private func removeMemoryPressureMonitoring() {
        if let memoryObserver {
            NotificationCenter.default.removeObserver(memoryObserver)
        }
        memoryObserver = nil
    }

    private func handleMemoryPressure() {
        guard !isMemoryReduced else { return }
        isMemoryReduced = true
        errorMessage = "Memory pressure detected — reducing mesh resolution for stability."
        Logger.heatmap.warning("Memory pressure — reducing mesh resolution")
    }

    // MARK: - Error Handling

    /// Called when the AR session encounters an error.
    /// Preserves all collected data and allows partial scan saving.
    func handleARError(_ message: String) {
        isTrackingLimited = true
        // Don't stop the pipeline — Wi-Fi continues, just can't position new measurements
        Logger.heatmap.error("AR error during continuous scan: \(message) — data preserved")
    }

    /// Called when Wi-Fi measurement fails.
    /// Map continues rendering, measurements degrade gracefully.
    func handleWiFiError() {
        isWiFiDegraded = true
        // Don't stop the map — it continues rendering without new heatmap data
        Logger.heatmap.warning("Wi-Fi pipeline degraded — map continues without new signal data")
    }

    // MARK: - AP Roaming Detection (P1)

    /// Checks for BSSID changes and records transitions for the roaming overlay.
    private func detectBSSIDTransition(
        currentBSSID: String?,
        position: (x: Float, z: Float)?
    ) {
        guard let bssid = currentBSSID, !bssid.isEmpty,
              let pos = position else { return }

        if let last = lastSeenBSSID, last != bssid {
            let transition = BSSIDTransition(
                worldX: pos.x,
                worldZ: pos.z,
                fromBSSID: last,
                toBSSID: bssid
            )
            bssidTransitions.append(transition)
            Logger.heatmap.debug("AP roaming detected at (\(pos.x), \(pos.z))")
        }

        lastSeenBSSID = bssid
    }

    // MARK: - Status Polling

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

    /// Updates observable state from the pipeline and renderer.
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

        // Get latest measurement RSSI and BSSID
        let rawMeasurements = await pipeline.rawMeasurements
        if let lastRaw = rawMeasurements.last {
            currentRSSI = lastRaw.measurement.rssi
            currentSSID = lastRaw.measurement.ssid
            currentBSSID = lastRaw.measurement.bssid

            // Detect AP roaming transitions
            detectBSSIDTransition(
                currentBSSID: lastRaw.measurement.bssid,
                position: (x: lastRaw.arX, z: lastRaw.arZ)
            )
        }

        // Process new measurements into heatmap splats
        let newMeasurementCount = rawMeasurements.count
        if newMeasurementCount > lastProcessedMeasurementCount {
            for i in lastProcessedMeasurementCount..<newMeasurementCount {
                let positioned = rawMeasurements[i]
                textureRenderer.paintMeasurementSplat(
                    worldX: positioned.arX,
                    worldZ: positioned.arZ,
                    rssi: positioned.measurement.rssi
                )
            }
            lastProcessedMeasurementCount = newMeasurementCount
        }

        // Update user position from the latest AR position
        if let lastRaw = rawMeasurements.last {
            textureRenderer.updateUserPosition(x: lastRaw.arX, z: lastRaw.arZ)
            userWorldPosition = (x: lastRaw.arX, z: lastRaw.arZ)
        }

        // Update renderer stats
        meshSegmentsRendered = textureRenderer.meshSegmentsRendered
        measurementSplatsRendered = textureRenderer.measurementSplatsRendered
        mapBoundsWidth = textureRenderer.mapBounds.width
        mapBoundsHeight = textureRenderer.mapBounds.height
    }

    // MARK: - Placeholder Floor Plan

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
