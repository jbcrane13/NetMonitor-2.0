import CoreGraphics
import Foundation
import ImageIO
import NetMonitorCore
import os
import SwiftUI

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
#endif

// MARK: - FloorPlanGenerationViewModel

/// ViewModel for the floor plan generation pipeline.
///
/// Manages AR mesh data accumulation, real-time preview generation,
/// coverage tracking, and final floor plan generation.
@MainActor
@Observable
final class FloorPlanGenerationViewModel {

    // MARK: - Observable State

    /// Current generation progress.
    private(set) var progress: FloorPlanGenerationProgress?

    /// Whether generation is in progress.
    private(set) var isGenerating = false

    /// The generated floor plan result.
    private(set) var generationResult: FloorPlanGenerationResult?

    /// Real-time preview image during scanning.
    private(set) var previewImage: CGImage?

    /// Coverage information for the current scan.
    private(set) var coverageInfo: ScanCoverageInfo?

    /// Error message if generation fails.
    var errorMessage: String?

    /// Whether the AR session is LiDAR capable.
    private(set) var isLiDAR: Bool

    /// Detected room transition boundaries (narrow passages < 1.5m between wall clusters).
    ///
    /// Room boundaries are detected during scanning as the user walks through doorways.
    /// Multi-room stitching is automatic: the pipeline processes all accumulated vertices
    /// from all rooms, producing a single combined floor plan image. Boundaries are metadata
    /// indicating where room transitions were detected.
    private(set) var roomBoundaries: [RoomBoundary] = []

    /// Whether the preview has recently expanded into a new spatial region.
    /// Set to true when new vertices extend significantly beyond the previous bounding box,
    /// indicating the user has walked into a new room.
    private(set) var didExpandIntoNewRegion = false

    /// Accumulated vertex count.
    var vertexCount: Int {
        accumulatedVertices.count
    }

    /// Accumulated plane count (non-LiDAR).
    var planeCount: Int {
        accumulatedPlanes.count
    }

    /// Whether enough data has been collected for generation.
    var hasEnoughData: Bool {
        if isLiDAR {
            return accumulatedVertices.count >= 100
        }
        return accumulatedPlanes.count >= 3
    }

    /// Coverage percentage (0-100).
    var coveragePercent: Double {
        coverageInfo?.coveragePercent ?? 0
    }

    /// Scanned area in square meters.
    var scannedAreaM2: Double {
        coverageInfo?.scannedAreaM2 ?? 0
    }

    /// Human-readable coverage label.
    var coverageLabel: String {
        let percent = Int(coveragePercent)
        let area = String(format: "%.1f", scannedAreaM2)
        return "\(percent)% • \(area) m²"
    }

    /// Progress fraction (0-1) for the generation pipeline.
    var progressFraction: Double {
        progress?.fractionComplete ?? 0
    }

    /// Progress message for the generation pipeline.
    var progressMessage: String {
        progress?.message ?? ""
    }

    // MARK: - Private State

    /// Accumulated 3D vertices from AR mesh (LiDAR).
    private var accumulatedVertices: [MeshVertex] = []

    /// Accumulated plane segments (non-LiDAR).
    private var accumulatedPlanes: [PlaneVertex] = []

    /// Detected floor Y coordinate.
    private var floorY: Float = 0

    /// Current spatial region encompassing all scanned vertices.
    /// Used to detect when the preview should expand into new regions.
    private var currentSpatialRegion: SpatialRegion?

    /// Threshold in meters for detecting significant region expansion (new room entry).
    private let regionExpansionThreshold: Float = 1.0

    /// Preview update timer task.
    private var previewUpdateTask: Task<Void, Never>?

    /// Throttle interval for preview updates (seconds).
    private let previewUpdateInterval: TimeInterval = 0.5

    /// Last preview update time.
    private var lastPreviewUpdate: Date = .distantPast

    // MARK: - Init

    init(isLiDAR: Bool = false) {
        self.isLiDAR = isLiDAR
    }

    // MARK: - Mesh Data Accumulation (LiDAR)

    #if os(iOS) && !targetEnvironment(simulator)
    /// Processes an ARMeshAnchor and accumulates its vertices.
    /// Extracts vertex positions from the mesh geometry, transforms them to
    /// world coordinates, and appends to the accumulated vertex buffer.
    /// Includes mesh classification data when available (LiDAR with meshWithClassification).
    ///
    /// Memory management: only stores transformed vertex positions, not raw mesh data.
    func processMeshAnchor(_ anchor: ARMeshAnchor) {
        let geometry = anchor.geometry
        let vertices = geometry.vertices
        let vertexCount = vertices.count

        // Extract and transform vertices to world coordinates
        let anchorTransform = anchor.transform

        // Build face-to-classification lookup if classification is available
        let faceClassifications = geometry.classification
        let faceCount = geometry.faces.count

        // Build vertex-to-face classification map
        // Each face has 3 vertices (indices). Assign face classification to each vertex.
        var vertexClassMap = [Int: MeshClassification]()
        if let faceClassifications {
            let faces = geometry.faces
            for faceIndex in 0 ..< faceCount {
                let classPointer = faceClassifications.buffer.contents()
                    .advanced(by: faceClassifications.offset + faceClassifications.stride * faceIndex)
                let classValue = classPointer.assumingMemoryBound(to: UInt8.self).pointee
                let classification = mapARMeshClassification(classValue)

                // Get the 3 vertex indices for this face
                let faceByteOffset = faces.indexCountPerPrimitive * faces.bytesPerIndex * faceIndex
                let indexPointer = faces.buffer.contents().advanced(by: faceByteOffset)
                for vi in 0 ..< faces.indexCountPerPrimitive {
                    let vertexIndex: Int
                    if faces.bytesPerIndex == 4 {
                        vertexIndex = Int(
                            indexPointer.advanced(by: vi * 4).assumingMemoryBound(to: UInt32.self).pointee
                        )
                    } else {
                        vertexIndex = Int(
                            indexPointer.advanced(by: vi * 2).assumingMemoryBound(to: UInt16.self).pointee
                        )
                    }
                    vertexClassMap[vertexIndex] = classification
                }
            }
        }

        var newVertices: [MeshVertex] = []
        newVertices.reserveCapacity(vertexCount)

        for i in 0 ..< vertexCount {
            let vertexPointer = vertices.buffer.contents()
                .advanced(by: vertices.offset + vertices.stride * i)
            let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee

            // Transform to world coordinates
            let worldPos = anchorTransform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0)
            let classification = vertexClassMap[i] ?? .none
            newVertices.append(MeshVertex(
                x: worldPos.x,
                y: worldPos.y,
                z: worldPos.z,
                classification: classification
            ))
        }

        accumulatedVertices.append(contentsOf: newVertices)
        updatePreviewIfNeeded()
    }

    /// Maps ARMeshClassification raw value to our MeshClassification enum.
    private func mapARMeshClassification(_ value: UInt8) -> MeshClassification {
        // ARMeshClassification values: 0=none, 1=wall, 2=floor, 3=ceiling, 4=table, 5=seat, 6=door, 7=window
        // Our enum has the same raw values except door/window are swapped
        switch value {
        case 0: return .none
        case 1: return .wall
        case 2: return .floor
        case 3: return .ceiling
        case 4: return .table
        case 5: return .seat
        case 6: return .door
        case 7: return .window
        default: return .none
        }
    }

    /// Processes an ARPlaneAnchor (non-LiDAR fallback).
    /// Extracts vertical plane boundaries for floor plan generation.
    func processPlaneAnchor(_ anchor: ARPlaneAnchor) {
        guard anchor.alignment == .vertical else { return }

        let anchorTransformPlane = anchor.transform
        let planeExtent = anchor.planeExtent
        let center = anchor.center

        // Compute world-space corners of the vertical plane
        let halfWidth = planeExtent.width / 2
        let localStart = SIMD4<Float>(center.x - halfWidth, center.y, center.z, 1.0)
        let localEnd = SIMD4<Float>(center.x + halfWidth, center.y, center.z, 1.0)

        let worldStart = anchorTransformPlane * localStart
        let worldEnd = anchorTransformPlane * localEnd

        let plane = PlaneVertex(
            startX: worldStart.x,
            startZ: worldStart.z,
            endX: worldEnd.x,
            endZ: worldEnd.z,
            width: 0.15 // Default wall thickness assumption
        )

        accumulatedPlanes.append(plane)
        updatePreviewIfNeeded()
    }
    #endif

    /// Adds mesh vertices directly (for testing or non-AR sources).
    func addVertices(_ vertices: [MeshVertex]) {
        accumulatedVertices.append(contentsOf: vertices)
        updatePreviewIfNeeded()
    }

    /// Adds plane vertices directly (for testing or non-AR sources).
    func addPlanes(_ planes: [PlaneVertex]) {
        accumulatedPlanes.append(contentsOf: planes)
        updatePreviewIfNeeded()
    }

    /// Updates the detected floor Y coordinate.
    func updateFloorY(_ y: Float) {
        floorY = y
    }

    // MARK: - Preview Update

    /// Throttled preview update to avoid excessive computation during scanning.
    ///
    /// The preview expands incrementally as the user moves into new rooms:
    /// - All accumulated vertices are processed each tick, so the bounding box
    ///   naturally grows to encompass new rooms
    /// - When the spatial region expands significantly (> 1m beyond previous bounds),
    ///   `didExpandIntoNewRegion` is set to signal the UI
    /// - Room boundaries are periodically re-detected from the full vertex set
    private func updatePreviewIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPreviewUpdate) >= previewUpdateInterval else { return }
        lastPreviewUpdate = now

        // Reset expansion flag each tick — will be set if expansion detected
        didExpandIntoNewRegion = false

        // Update coverage info and preview
        if isLiDAR {
            coverageInfo = FloorPlanGenerationPipeline.computeCoverage(
                vertices: accumulatedVertices,
                floorY: floorY
            )

            // Generate real-time preview (processes ALL vertices — multi-room automatic)
            previewImage = FloorPlanGenerationPipeline.generatePreview(
                vertices: accumulatedVertices,
                floorY: floorY
            )

            // Check for spatial region expansion (new room entry)
            detectSpatialExpansion(vertices: accumulatedVertices)

            // Periodically detect room boundaries
            if accumulatedVertices.count >= 100 {
                roomBoundaries = FloorPlanGenerationPipeline.detectRoomBoundaries(
                    vertices: accumulatedVertices,
                    floorY: floorY
                )
            }
        } else if !accumulatedPlanes.isEmpty {
            // For non-LiDAR, generate coverage from plane data
            let planeVertices = planesToMeshVertices(accumulatedPlanes)
            coverageInfo = FloorPlanGenerationPipeline.computeCoverage(
                vertices: planeVertices,
                floorY: 0
            )
            previewImage = FloorPlanGenerationPipeline.generatePreview(
                vertices: planeVertices,
                floorY: 0
            )

            // Check for spatial region expansion
            detectSpatialExpansion(vertices: planeVertices)
        }
    }

    /// Detects whether the scanned area has significantly expanded, indicating
    /// the user has moved into a new room.
    ///
    /// Compares the current vertex bounding box against the previously recorded
    /// spatial region. If any edge has expanded by more than `regionExpansionThreshold`
    /// meters, marks `didExpandIntoNewRegion` as true and updates the region.
    private func detectSpatialExpansion(vertices: [MeshVertex]) {
        guard let newRegion = FloorPlanGenerationPipeline.computeSpatialRegion(
            vertices: vertices,
            floorY: floorY
        ) else { return }

        if let existing = currentSpatialRegion {
            // Check if any edge has expanded significantly
            let expandedMinX = existing.minX - newRegion.minX > regionExpansionThreshold
            let expandedMaxX = newRegion.maxX - existing.maxX > regionExpansionThreshold
            let expandedMinZ = existing.minZ - newRegion.minZ > regionExpansionThreshold
            let expandedMaxZ = newRegion.maxZ - existing.maxZ > regionExpansionThreshold

            if expandedMinX || expandedMaxX || expandedMinZ || expandedMaxZ {
                didExpandIntoNewRegion = true
            }
        }

        currentSpatialRegion = newRegion
    }

    // MARK: - Floor Plan Generation

    /// Generates the final floor plan from accumulated data.
    /// This is the "Done Scanning" action.
    func generateFloorPlan() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        progress = nil

        // Run generation off the main thread to avoid blocking UI
        let vertices = accumulatedVertices
        let planes = accumulatedPlanes
        let lidar = isLiDAR
        let floor = floorY

        let result: FloorPlanGenerationResult? = await Task.detached(priority: .userInitiated) {
            if lidar {
                return FloorPlanGenerationPipeline.generateFromMesh(
                    vertices: vertices,
                    floorY: floor
                ) { progress in
                    Task { @MainActor in
                        self.progress = progress
                    }
                }
            } else {
                return FloorPlanGenerationPipeline.generateFromPlanes(
                    planes: planes
                ) { progress in
                    Task { @MainActor in
                        self.progress = progress
                    }
                }
            }
        }.value

        if let result {
            generationResult = result
            progress = FloorPlanGenerationProgress(
                phase: .complete,
                fractionComplete: 1.0,
                message: "Floor plan generated"
            )
            Logger.heatmap.info("Floor plan generated: \(result.pixelWidth)x\(result.pixelHeight)")
        } else {
            errorMessage = "Not enough data to generate a floor plan. Continue scanning to capture more walls."
            progress = nil
        }

        // Memory management: discard raw mesh data after generation
        discardRawMeshData()
        isGenerating = false
    }

    /// Creates a FloorPlan model from the generation result.
    func createFloorPlan() -> FloorPlan? {
        guard let result = generationResult else { return nil }

        // Convert CGImage to PNG data
        guard let pngData = cgImageToPNGData(result.image) else { return nil }

        return FloorPlan(
            imageData: pngData,
            widthMeters: result.widthMeters,
            heightMeters: result.heightMeters,
            pixelWidth: result.pixelWidth,
            pixelHeight: result.pixelHeight,
            origin: .arGenerated
        )
    }

    /// Creates a SurveyProject from the generation result.
    func createSurveyProject(name: String) -> SurveyProject? {
        guard let floorPlan = createFloorPlan() else { return nil }

        return SurveyProject(
            name: name,
            floorPlan: floorPlan,
            surveyMode: .arAssisted
        )
    }

    // MARK: - Memory Management

    /// Discards raw mesh data after floor plan generation to free memory.
    func discardRawMeshData() {
        accumulatedVertices.removeAll(keepingCapacity: false)
        accumulatedPlanes.removeAll(keepingCapacity: false)
    }

    /// Resets all state for a new scan.
    func reset() {
        accumulatedVertices.removeAll(keepingCapacity: false)
        accumulatedPlanes.removeAll(keepingCapacity: false)
        floorY = 0
        progress = nil
        isGenerating = false
        generationResult = nil
        previewImage = nil
        coverageInfo = nil
        errorMessage = nil
        roomBoundaries = []
        currentSpatialRegion = nil
        didExpandIntoNewRegion = false
        previewUpdateTask?.cancel()
        previewUpdateTask = nil
        lastPreviewUpdate = .distantPast
    }

    // MARK: - Private Helpers

    /// Converts plane vertices to mesh vertices for coverage/preview computation.
    private func planesToMeshVertices(_ planes: [PlaneVertex]) -> [MeshVertex] {
        var vertices: [MeshVertex] = []
        for plane in planes {
            // Place at wall height (1.5m) for height filtering to work
            vertices.append(MeshVertex(x: plane.startX, y: 1.5, z: plane.startZ))
            vertices.append(MeshVertex(x: plane.endX, y: 1.5, z: plane.endZ))
        }
        return vertices
    }

    /// Converts CGImage to PNG data.
    private func cgImageToPNGData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}
