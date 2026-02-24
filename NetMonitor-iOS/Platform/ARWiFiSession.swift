import Foundation
import SwiftUI

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit

/// Manages the ARKit session and RealityKit scene for the AR WiFi Signal view.
///
/// Creates `ModelEntity` spheres in world space, color-coded by signal strength,
/// so users can see how signal quality varies as they move around the space.
@MainActor
final class ARWiFiSession: NSObject {
    let arView: ARView

    /// True when `ARWorldTrackingConfiguration` is available on this device.
    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    override init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        super.init()
        arView.session.delegate = self
    }

    // MARK: - Session Lifecycle

    func startSession() {
        guard ARWiFiSession.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        config.environmentTexturing = .none
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopSession() {
        arView.session.pause()
    }

    // MARK: - Signal Anchor Placement

    /// Places a color-coded sphere in the AR scene at 0.5 m in front of the current camera.
    /// - Parameter signalDBm: Signal strength in approximate dBm.
    func placeSignalAnchor(signalDBm: Int) {
        guard let frame = arView.session.currentFrame else { return }

        // Position 0.5 m in front of the camera
        var translation = matrix_identity_float4x4
        translation.columns.3.z = -0.5
        let transform = simd_mul(frame.camera.transform, translation)
        let position = SIMD3<Float>(transform.columns.3.x,
                                   transform.columns.3.y,
                                   transform.columns.3.z)

        let anchor = AnchorEntity(world: position)
        anchor.addChild(makeSignalEntity(signalDBm: signalDBm))
        arView.scene.addAnchor(anchor)
    }

    // MARK: - Helpers

    private func makeSignalEntity(signalDBm: Int) -> ModelEntity {
        let color = UIColor.signalColor(dBm: signalDBm)
        var material = SimpleMaterial()
        material.color = .init(tint: color, texture: nil)
        material.roughness = 0.5
        material.metallic = 0.1
        return ModelEntity(mesh: .generateSphere(radius: 0.04), materials: [material])
    }
}

// MARK: - ARSessionDelegate

extension ARWiFiSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {}
    nonisolated func sessionWasInterrupted(_ session: ARSession) {}
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {}
}

#else

/// Stub for the simulator and macOS where ARKit camera AR is unavailable.
@MainActor
final class ARWiFiSession: NSObject {
    static var isSupported: Bool { false }

    override init() { super.init() }

    func startSession() {}
    func stopSession() {}
    func placeSignalAnchor(signalDBm: Int) {}
}

#endif

#if os(iOS)
// MARK: - UIColor Signal Color Helper

extension UIColor {
    /// Returns green (> -50 dBm), yellow (-50 to -70 dBm), or red (< -70 dBm).
    static func signalColor(dBm: Int) -> UIColor {
        if dBm > -50 { return .systemGreen }
        if dBm > -70 { return .systemYellow }
        return .systemRed
    }
}
#endif
