import Foundation
import SwiftUI

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit

// MARK: - ARContinuousHeatmapSession (real device)

/// Manages the ARKit world-tracking session and the RealityKit floor grid plane.
///
/// - Starts a world-tracking configuration with horizontal plane detection.
/// - On first detected horizontal plane, creates and anchors a 10 m × 10 m flat
///   `ModelEntity` with an `UnlitMaterial`. Callers update the texture via
///   `updateGridTexture(_:)`.
/// - Provides `worldToGridCell(gridSize:)` to map camera world XZ position
///   onto a grid cell index.
@MainActor
final class ARContinuousHeatmapSession: NSObject, @unchecked Sendable {

    // MARK: - Constants

    /// Side length of the AR floor plane in meters.
    static let planeSizeMeters: Float = 10.0
    /// Minimum camera movement (meters) before a new cell is recorded.
    static let distanceGate: Float = 0.3

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    // MARK: - Public

    let arView: ARView

    /// Called on the main actor when the first horizontal plane is detected.
    var onFloorDetected: (() -> Void)?

    // MARK: - Private

    private var floorAnchorEntity: AnchorEntity?
    private var gridPlaneEntity: ModelEntity?
    /// Store the transform value only — never the ARPlaneAnchor itself.
    /// ARPlaneAnchor is updated every frame and holds back-references to recent
    /// ARFrames; keeping it on the session delegate causes ARFrame retention warnings.
    private var floorAnchorTransform: simd_float4x4?
    private var hasDetectedFloor = false

    // MARK: - Init

    override init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        super.init()
        arView.session.delegate = self
    }

    // MARK: - Lifecycle

    func startSession() {
        guard Self.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        hasDetectedFloor = false
        floorAnchorEntity = nil
        gridPlaneEntity = nil
        floorAnchorTransform = nil
    }

    func stopSession() {
        arView.session.pause()
    }

    // MARK: - Position

    /// The camera's current position in world space, or nil if no frame is available.
    var currentWorldPosition: SIMD3<Float>? {
        guard let frame = arView.session.currentFrame else { return nil }
        let col = frame.camera.transform.columns.3
        return SIMD3(col.x, col.y, col.z)
    }

    // MARK: - Grid Mapping

    /// Convert the camera's current world XZ position to a grid (col, row) index.
    ///
    /// The floor plane is `planeSizeMeters × planeSizeMeters`, centred at the
    /// plane anchor's origin. (col, row) are clamped to `[0, gridSize-1]`.
    ///
    /// Returns nil if there is no floor anchor or no current frame.
    func worldToGridCell(gridSize: Int) -> (col: Int, row: Int)? {
        guard let anchorTransform = floorAnchorTransform,
              let frame = arView.session.currentFrame else { return nil }

        // World position of camera
        let camWorld = frame.camera.transform.columns.3
        let camPos = SIMD4<Float>(camWorld.x, camWorld.y, camWorld.z, 1)

        // Transform into floor-plane local space
        let invAnchor = anchorTransform.inverse
        let localPos = invAnchor * camPos

        // localPos.x and localPos.z are the in-plane coordinates
        // Plane spans [-planeSizeMeters/2 … +planeSizeMeters/2] on both axes
        let half = Self.planeSizeMeters / 2.0
        let normX = (localPos.x + half) / Self.planeSizeMeters  // 0…1
        let normZ = (localPos.z + half) / Self.planeSizeMeters  // 0…1

        let col = Int((normX * Float(gridSize)).rounded(.down)).clamped(to: 0...(gridSize - 1))
        let row = Int((normZ * Float(gridSize)).rounded(.down)).clamped(to: 0...(gridSize - 1))
        return (col, row)
    }

    // MARK: - Texture

    /// Replace the floor plane entity's material texture with the given image.
    /// Call this each time the grid state changes.
    func updateGridTexture(_ image: UIImage) {
        guard let entity = gridPlaneEntity else { return }
        guard let cgImage = image.cgImage else { return }
        let options = TextureResource.CreateOptions(semantic: .color)
        guard let texture = try? TextureResource.generate(from: cgImage, options: options) else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: .white.withAlphaComponent(0.9), texture: .init(texture))
        entity.model?.materials = [material]
    }

    // MARK: - Private helpers

    private func createFloorPlane(for anchor: ARPlaneAnchor) {
        guard !hasDetectedFloor else { return }
        hasDetectedFloor = true

        // Copy the transform value — do NOT store the ARPlaneAnchor reference.
        let capturedTransform = anchor.transform
        floorAnchorTransform = capturedTransform

        let size = Self.planeSizeMeters
        let mesh = MeshResource.generatePlane(width: size, depth: size)
        var material = UnlitMaterial()
        material.color = .init(tint: .black.withAlphaComponent(0.01))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        // Rotate 90° around X so the plane lies flat (RealityKit planes are vertical by default)
        entity.transform.rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))

        // Use a world-transform anchor instead of AnchorEntity(anchor:) to avoid
        // holding a strong reference to the ARPlaneAnchor (which retains ARFrames).
        let anchorEntity = AnchorEntity(world: capturedTransform)
        anchorEntity.addChild(entity)
        arView.scene.addAnchor(anchorEntity)

        floorAnchorEntity = anchorEntity
        gridPlaneEntity = entity

        Task { @MainActor in
            self.onFloorDetected?()
        }
    }
}

// MARK: - ARSessionDelegate

extension ARContinuousHeatmapSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let plane = anchor as? ARPlaneAnchor,
                  plane.alignment == .horizontal else { continue }
            Task { @MainActor in
                self.createFloorPlane(for: plane)
            }
            return
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {}
    nonisolated func sessionWasInterrupted(_ session: ARSession) {}
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {}
}

// MARK: - Comparable extension for clamping

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

#else

// MARK: - ARContinuousHeatmapSession (simulator stub)

@MainActor
final class ARContinuousHeatmapSession: NSObject {
    static var isSupported: Bool { false }
    static let distanceGate: Float = 0.3
    static let planeSizeMeters: Float = 10.0

    var onFloorDetected: (() -> Void)?

    override init() { super.init() }

    func startSession() {}
    func stopSession() {}

    var currentWorldPosition: SIMD3<Float>? { nil }

    func worldToGridCell(gridSize: Int) -> (col: Int, row: Int)? { nil }

    func updateGridTexture(_ image: UIImage) {}
}

#endif
