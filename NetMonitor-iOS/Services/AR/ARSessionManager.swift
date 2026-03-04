import AVFoundation
import Foundation
import os
import SwiftUI

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit
#endif

// MARK: - ARDeviceCapability

/// Describes the AR capability level of the current device.
public enum ARDeviceCapability: Sendable, Equatable {
    /// Device has LiDAR sensor — full mesh reconstruction available.
    case lidar
    /// Device supports AR world tracking but no LiDAR — plane detection only.
    case nonLiDAR
    /// Device does not support ARKit at all.
    case unsupported
}

// MARK: - ARSessionState

/// Tracks the current state of the AR scanning session.
enum ARSessionState: Sendable, Equatable {
    case idle
    case waitingForPermission
    case starting
    case running
    case paused
    case error(String)
}

// MARK: - ARSurfaceType

/// Classification of detected AR surfaces for visualization.
enum ARSurfaceType: Sendable, Equatable {
    case floor
    case wall
    case ceiling
    case other
}

// MARK: - DetectedSurface

/// A surface detected during an AR session.
struct DetectedSurface: Identifiable, Sendable, Equatable {
    let id: UUID
    let surfaceType: ARSurfaceType
    let area: Float // in square meters

    init(id: UUID = UUID(), surfaceType: ARSurfaceType, area: Float) {
        self.id = id
        self.surfaceType = surfaceType
        self.area = area
    }
}

// MARK: - ARSessionManager

/// Manages the AR session lifecycle, configuration, and surface detection.
///
/// Handles LiDAR vs non-LiDAR configuration, camera permission, and delegates
/// surface classification information to the view layer. Uses UIViewRepresentable
/// pattern with ARView from RealityKit.
@MainActor
final class ARSessionManager: NSObject {

    // MARK: - State

    private(set) var sessionState: ARSessionState = .idle
    private(set) var detectedSurfaces: [DetectedSurface] = []
    private(set) var deviceCapability: ARDeviceCapability
    var onStateChange: ((ARSessionState) -> Void)?
    var onSurfaceDetected: (([DetectedSurface]) -> Void)?

    // MARK: - AR Components

    #if os(iOS) && !targetEnvironment(simulator)
    let arView: ARView
    #endif

    // MARK: - Init

    override init() {
        self.deviceCapability = ARSessionManager.detectCapability()
        #if os(iOS) && !targetEnvironment(simulator)
        self.arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        #endif
        super.init()
        #if os(iOS) && !targetEnvironment(simulator)
        arView.session.delegate = self
        #endif
    }

    // MARK: - Device Capability Detection

    /// Detects the AR capability of the current device.
    static func detectCapability() -> ARDeviceCapability {
        #if os(iOS) && !targetEnvironment(simulator)
        guard ARWorldTrackingConfiguration.isSupported else {
            return .unsupported
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            return .lidar
        }
        return .nonLiDAR
        #else
        return .unsupported
        #endif
    }

    /// Returns the appropriate ARKit configuration for the device.
    ///
    /// - LiDAR: mesh reconstruction with classification + horizontal/vertical plane detection
    /// - Non-LiDAR: horizontal + vertical plane detection only
    /// - Unsupported: returns nil
    static func makeConfiguration(for capability: ARDeviceCapability) -> Any? {
        #if os(iOS) && !targetEnvironment(simulator)
        guard capability != .unsupported else { return nil }

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        if capability == .lidar {
            config.sceneReconstruction = .meshWithClassification
        }

        return config
        #else
        return nil
        #endif
    }

    // MARK: - Camera Permission

    /// Checks the current camera authorization status.
    static func cameraAuthorizationStatus() -> CameraPermissionStatus {
        #if os(iOS)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
        #else
        return .denied
        #endif
    }

    /// Requests camera permission and returns the result.
    func requestCameraPermission() async -> CameraPermissionStatus {
        #if os(iOS)
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
        #else
        return .denied
        #endif
    }

    // MARK: - Session Lifecycle

    /// Starts the AR session with the appropriate configuration for the device.
    func startSession() {
        guard deviceCapability != .unsupported else {
            sessionState = .error("ARKit is not supported on this device.")
            onStateChange?(sessionState)
            return
        }

        #if os(iOS) && !targetEnvironment(simulator)
        guard let config = ARSessionManager.makeConfiguration(for: deviceCapability)
            as? ARWorldTrackingConfiguration
        else {
            sessionState = .error("Failed to create AR configuration.")
            onStateChange?(sessionState)
            return
        }

        sessionState = .starting
        onStateChange?(sessionState)

        // Enable mesh visualization for LiDAR devices
        if deviceCapability == .lidar {
            arView.debugOptions.insert(.showSceneUnderstanding)
        }

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        sessionState = .running
        onStateChange?(sessionState)
        Logger.heatmap.info("AR session started with capability: \(String(describing: self.deviceCapability))")
        #else
        sessionState = .error("AR is not available in the simulator.")
        onStateChange?(sessionState)
        #endif
    }

    /// Pauses the AR session.
    func pauseSession() {
        #if os(iOS) && !targetEnvironment(simulator)
        arView.session.pause()
        sessionState = .paused
        onStateChange?(sessionState)
        Logger.heatmap.info("AR session paused")
        #endif
    }

    /// Stops the AR session and releases resources.
    func stopSession() {
        #if os(iOS) && !targetEnvironment(simulator)
        arView.session.pause()
        arView.scene.anchors.removeAll()
        #endif
        detectedSurfaces.removeAll()
        sessionState = .idle
        onStateChange?(sessionState)
        Logger.heatmap.info("AR session stopped")
    }

    // MARK: - Surface Classification

    #if os(iOS) && !targetEnvironment(simulator)
    /// Classifies an ARPlaneAnchor into an ARSurfaceType.
    static func classifyPlane(_ anchor: ARPlaneAnchor) -> ARSurfaceType {
        switch anchor.alignment {
        case .horizontal:
            // Use center height to distinguish floor from ceiling
            if anchor.center.y < 0.3 {
                return .floor
            } else {
                return .ceiling
            }
        case .vertical:
            return .wall
        @unknown default:
            return .other
        }
    }

    /// Adds colored visualization for detected planes.
    func addSurfaceVisualization(for anchor: ARPlaneAnchor, node: AnchorEntity) {
        let surfaceType = ARSessionManager.classifyPlane(anchor)
        let extent = anchor.extent
        let area = extent.x * extent.z

        let color: UIColor
        switch surfaceType {
        case .floor:
            color = UIColor.systemGreen.withAlphaComponent(0.3)
        case .wall:
            color = UIColor.systemBlue.withAlphaComponent(0.3)
        case .ceiling:
            color = UIColor.systemPurple.withAlphaComponent(0.2)
        case .other:
            color = UIColor.systemGray.withAlphaComponent(0.2)
        }

        var material = SimpleMaterial()
        material.color = .init(tint: color, texture: nil)
        material.roughness = 0.9
        material.metallic = 0.0

        let mesh = MeshResource.generatePlane(
            width: extent.x,
            depth: extent.z
        )
        let entity = ModelEntity(mesh: mesh, materials: [material])
        node.addChild(entity)

        // Track detected surface
        let surface = DetectedSurface(surfaceType: surfaceType, area: area)
        detectedSurfaces.append(surface)
        onSurfaceDetected?(detectedSurfaces)
    }
    #endif
}

// MARK: - CameraPermissionStatus

/// Camera authorization status for UI display.
enum CameraPermissionStatus: Sendable, Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

// MARK: - ARSessionDelegate

#if os(iOS) && !targetEnvironment(simulator)
extension ARSessionManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
                let anchorEntity = AnchorEntity(anchor: planeAnchor)
                addSurfaceVisualization(for: planeAnchor, node: anchorEntity)
                arView.scene.addAnchor(anchorEntity)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Surface updates are handled by ARKit's built-in plane merging
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            let message: String
            if let arError = error as? ARError {
                switch arError.code {
                case .cameraUnauthorized:
                    message = "Camera access is required for AR scanning. Please enable it in Settings."
                case .sensorUnavailable:
                    message = "Required sensors are not available."
                case .sensorFailed:
                    message = "A sensor failure occurred. Please restart the scan."
                case .worldTrackingFailed:
                    message = "World tracking failed. Move to a well-lit area."
                default:
                    message = "AR session error: \(error.localizedDescription)"
                }
            } else {
                message = "AR session error: \(error.localizedDescription)"
            }
            sessionState = .error(message)
            onStateChange?(sessionState)
            Logger.heatmap.error("AR session failed: \(error.localizedDescription)")
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            sessionState = .paused
            onStateChange?(sessionState)
            Logger.heatmap.info("AR session interrupted")
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            sessionState = .running
            onStateChange?(sessionState)
            Logger.heatmap.info("AR session interruption ended")
        }
    }
}
#endif
