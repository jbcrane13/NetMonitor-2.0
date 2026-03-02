import Foundation
import SwiftUI

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit

/// Manages an ARKit world-tracking session for continuous WiFi heatmap surveying.
///
/// Tracks the device's XZ (horizontal plane) position and places color-coded spheres
/// at each recorded measurement point. The distance gate prevents duplicate readings
/// when standing still.
@MainActor
final class ARHeatmapSession: NSObject, @unchecked Sendable {
    let arView: ARView

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    /// Minimum distance (meters) the device must move before a new point is recorded.
    static let distanceGate: Float = 0.3

    override init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        super.init()
        arView.session.delegate = self
    }

    // MARK: - Session Lifecycle

    func startSession() {
        guard Self.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        // Enable plane detection so ARKit builds spatial understanding of the room
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        // Enable scene reconstruction on LiDAR devices for mesh-based room scanning
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        // Enable scene geometry for better spatial understanding
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        arView.environment.sceneUnderstanding.options.insert(.receivesLighting)
        arView.debugOptions.insert(.showSceneUnderstanding)

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopSession() {
        arView.session.pause()
    }

    // MARK: - Position Tracking

    /// Returns the camera's current XZ world position, or nil if no frame is available.
    var currentXZPosition: SIMD2<Float>? {
        guard let frame = arView.session.currentFrame else { return nil }
        let transform = frame.camera.transform
        return SIMD2(transform.columns.3.x, transform.columns.3.z)
    }

    // MARK: - Signal Anchor Placement

    /// Places a color-coded sphere at the camera's current ground-plane position.
    func placeSignalSphere(signalDBm: Int) {
        guard let frame = arView.session.currentFrame else { return }
        let camTransform = frame.camera.transform
        // Place sphere slightly below camera height so it's visible as you walk
        let camY = camTransform.columns.3.y
        let position = SIMD3<Float>(
            camTransform.columns.3.x,
            camY - 0.3,  // 30cm below eye level
            camTransform.columns.3.z
        )
        let anchor = AnchorEntity(world: position)
        anchor.addChild(makeSignalEntity(signalDBm: signalDBm))
        arView.scene.addAnchor(anchor)
    }

    // MARK: - Helpers

    private func makeSignalEntity(signalDBm: Int) -> ModelEntity {
        let color = UIColor.signalColor(dBm: signalDBm)
        var material = SimpleMaterial()
        material.color = .init(tint: color, texture: nil)
        material.roughness = 0.3
        material.metallic = 0.2
        // 8cm radius — visible from a few meters away
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.08), materials: [material])
        sphere.components[OpacityComponent.self] = OpacityComponent(opacity: 0.8)
        return sphere
    }
}

// MARK: - ARSessionDelegate

extension ARHeatmapSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {}
    nonisolated func sessionWasInterrupted(_ session: ARSession) {}
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {}
}

#else

/// Stub for the simulator where ARKit is unavailable.
@MainActor
final class ARHeatmapSession: NSObject {
    static var isSupported: Bool { false }
    static let distanceGate: Float = 0.3

    override init() { super.init() }

    func startSession() {}
    func stopSession() {}

    var currentXZPosition: SIMD2<Float>? {
        nil
    }

    func placeSignalSphere(signalDBm: Int) {}
}

#endif
