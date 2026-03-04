import CoreGraphics
import Foundation
import NetMonitorCore
import os
import UIKit

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit
#endif

// MARK: - ContinuousScanViewModel

/// ViewModel for the Phase 3 AR Continuous Scan feature.
///
/// Coordinates the concurrent AR session + Wi-Fi capture pipeline,
/// manages the Metal rendering pipeline, and provides observable state
/// for the split-screen UI (AR camera top 40%, 2D map bottom 60%).
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

    // MARK: - Metal Rendering State

    /// The current composite map+heatmap frame as a UIImage.
    private(set) var mapImage: UIImage?

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

    // MARK: - Coverage & Stats

    /// Coverage percentage estimate.
    var coveragePercentage: Double {
        // Estimate: each grid cell is ~0.5m², assume scanned area
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
    private var statusPollingTask: Task<Void, Never>?
    private var lastProcessedMeasurementCount = 0
    private var lastProcessedMeshCount = 0

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
        self.textureRenderer = HeatmapTextureRenderer()

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
        isScanning = true
        isPaused = false

        // Start the Metal render loop at 10Hz
        textureRenderer.startRenderLoop()

        // Start status polling
        startStatusPolling()

        Logger.heatmap.info("Continuous scan started with Metal rendering at \(HeatmapTextureRenderer.renderHz)Hz")
    }

    /// Pauses the scan — stops AR tracking + Wi-Fi measurement.
    func pauseScan() async {
        sessionManager.pauseSession()
        await pipeline.stop()
        textureRenderer.stopRenderLoop()
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
        textureRenderer.startRenderLoop()
        isPaused = false

        startStatusPolling()

        Logger.heatmap.info("Continuous scan resumed")
    }

    /// Finishes the scan and creates a SurveyProject with the collected data.
    func finishScan() async {
        // Stop everything
        await pipeline.stop()
        textureRenderer.stopRenderLoop()
        stopStatusPolling()
        isScanning = false
        isPaused = false

        // Get the downsampled measurements
        let points = await pipeline.getDownsampledPoints()

        // Create floor plan from the final map snapshot
        let floorPlanImageData = textureRenderer.renderSnapshot()?.pngData() ?? createPlaceholderFloorPlan()

        let mapWidth = max(1.0, mapBoundsWidth)
        let mapHeight = max(1.0, mapBoundsHeight)

        let floorPlan = FloorPlan(
            imageData: floorPlanImageData,
            widthMeters: Double(mapWidth),
            heightMeters: Double(mapHeight),
            pixelWidth: HeatmapTextureRenderer.textureSize,
            pixelHeight: HeatmapTextureRenderer.textureSize,
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
        textureRenderer.stopRenderLoop()
        stopStatusPolling()
        sessionManager.stopSession()
        isScanning = false
        isPaused = false
        rawMeasurementCount = 0
        downsampledPointCount = 0
        mapImage = nil

        Logger.heatmap.info("Continuous scan cancelled")
    }

    /// Cleans up all resources.
    func cleanup() async {
        await pipeline.stop()
        textureRenderer.stopRenderLoop()
        textureRenderer.cleanup()
        stopStatusPolling()
        sessionManager.stopSession()
    }

    /// Provides the ARSessionManager for the UIViewRepresentable wrapper.
    var arSessionManagerForView: ARSessionManager {
        sessionManager
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
        let vertices = anchor.geometry.vertices
        let faces = anchor.geometry.faces
        let transform = anchor.transform

        // Extract wall-height vertices and project to XZ plane
        let vertexCount = vertices.count
        guard vertexCount > 0 else { return }

        // Get vertex positions in world space
        for faceIdx in 0..<faces.count {
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

            // Get vertex positions and transform to world space
            let v0 = worldPosition(vertices: vertices, index: i0, transform: transform)
            let v1 = worldPosition(vertices: vertices, index: i1, transform: transform)
            let v2 = worldPosition(vertices: vertices, index: i2, transform: transform)

            // Height filter: only wall-height geometry (0.5m to 2.5m)
            let minY = min(v0.y, min(v1.y, v2.y))
            let maxY = max(v0.y, max(v1.y, v2.y))

            if maxY >= 0.5 && minY <= 2.5 {
                // Rasterize triangle edges as wall segments on the map
                textureRenderer.rasterizeWallSegment(x1: v0.x, z1: v0.z, x2: v1.x, z2: v1.z)
                textureRenderer.rasterizeWallSegment(x1: v1.x, z1: v1.z, x2: v2.x, z2: v2.z)
                textureRenderer.rasterizeWallSegment(x1: v2.x, z1: v2.z, x2: v0.x, z2: v0.z)
            } else if maxY < 0.5 {
                // Floor geometry - rasterize as floor area
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

        // Get latest measurement RSSI
        let rawMeasurements = await pipeline.rawMeasurements
        if let lastRaw = rawMeasurements.last {
            currentRSSI = lastRaw.measurement.rssi
            currentSSID = lastRaw.measurement.ssid
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
