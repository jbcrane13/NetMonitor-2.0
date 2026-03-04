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
    ///
    /// Memory management: only stores transformed vertex positions, not raw mesh data.
    func processMeshAnchor(_ anchor: ARMeshAnchor) {
        let geometry = anchor.geometry
        let vertices = geometry.vertices
        let vertexCount = vertices.count

        // Extract and transform vertices to world coordinates
        let transform = anchor.transform

        var newVertices: [MeshVertex] = []
        newVertices.reserveCapacity(vertexCount)

        for i in 0 ..< vertexCount {
            let vertexPointer = vertices.buffer.contents()
                .advanced(by: vertices.offset + vertices.stride * i)
            let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee

            // Transform to world coordinates
            let worldPos = transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0)
            newVertices.append(MeshVertex(x: worldPos.x, y: worldPos.y, z: worldPos.z))
        }

        accumulatedVertices.append(contentsOf: newVertices)
        updatePreviewIfNeeded()
    }

    /// Processes an ARPlaneAnchor (non-LiDAR fallback).
    /// Extracts vertical plane boundaries for floor plan generation.
    func processPlaneAnchor(_ anchor: ARPlaneAnchor) {
        guard anchor.alignment == .vertical else { return }

        let transform = anchor.transform
        let extent = anchor.extent
        let center = anchor.center

        // Compute world-space corners of the vertical plane
        let halfWidth = extent.x / 2
        let localStart = SIMD4<Float>(center.x - halfWidth, center.y, center.z, 1.0)
        let localEnd = SIMD4<Float>(center.x + halfWidth, center.y, center.z, 1.0)

        let worldStart = transform * localStart
        let worldEnd = transform * localEnd

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
    private func updatePreviewIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPreviewUpdate) >= previewUpdateInterval else { return }
        lastPreviewUpdate = now

        // Update coverage info
        if isLiDAR {
            coverageInfo = FloorPlanGenerationPipeline.computeCoverage(
                vertices: accumulatedVertices,
                floorY: floorY
            )

            // Generate real-time preview
            previewImage = FloorPlanGenerationPipeline.generatePreview(
                vertices: accumulatedVertices,
                floorY: floorY
            )
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
        }
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
