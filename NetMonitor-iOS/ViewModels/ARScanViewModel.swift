import Foundation
import os
import SwiftUI

// MARK: - ARScanViewModel

/// ViewModel for the Phase 2 AR-Assisted Map Creation scan view.
///
/// Manages AR session lifecycle, device capability detection, camera permission,
/// and surface detection state. Provides UI state for the scan instruction overlay,
/// non-LiDAR guidance, and error handling.
@MainActor
@Observable
final class ARScanViewModel {

    // MARK: - Observable State

    /// Current device AR capability (LiDAR, non-LiDAR, or unsupported).
    private(set) var deviceCapability: ARDeviceCapability

    /// Current AR session state.
    private(set) var sessionState: ARSessionState = .idle

    /// Camera permission status.
    private(set) var cameraPermission: CameraPermissionStatus

    /// Detected surfaces during scanning.
    private(set) var detectedSurfaces: [DetectedSurface] = []

    /// Count of detected wall surfaces.
    var wallCount: Int {
        detectedSurfaces.filter { $0.surfaceType == .wall }.count
    }

    /// Count of detected floor surfaces.
    var floorCount: Int {
        detectedSurfaces.filter { $0.surfaceType == .floor }.count
    }

    /// Whether surfaces have been detected (walls or floors visible).
    var hasSurfacesDetected: Bool {
        !detectedSurfaces.isEmpty
    }

    /// Whether the scan is actively running.
    var isScanning: Bool {
        sessionState == .running
    }

    /// Whether the device has LiDAR capability.
    var isLiDAR: Bool {
        deviceCapability == .lidar
    }

    /// Whether the device supports AR at all.
    var isARSupported: Bool {
        deviceCapability != .unsupported
    }

    /// Whether to show the scan instruction overlay.
    var showInstructions: Bool {
        sessionState == .running && !hasStartedScanning
    }

    /// Error message to display, if any.
    var errorMessage: String?

    /// Instructional text for the current state.
    var instructionText: String {
        switch sessionState {
        case .idle:
            return "Tap Start to begin scanning your space."
        case .waitingForPermission:
            return "Camera permission is required for AR scanning."
        case .starting:
            return "Starting AR session…"
        case .running:
            if !hasSurfacesDetected {
                return "Point your camera at walls and floors. Move slowly."
            }
            if deviceCapability == .lidar {
                return "Scanning with LiDAR. Walk slowly around the room."
            }
            return "Scanning surfaces. Move slowly for best results."
        case .paused:
            return "Scan paused. Resume to continue."
        case .error(let message):
            return message
        }
    }

    /// Guidance text for non-LiDAR devices.
    var nonLiDARGuidanceText: String? {
        guard deviceCapability == .nonLiDAR else { return nil }
        return "Your device does not have LiDAR. Scanning will use plane detection "
            + "with reduced precision (~30cm accuracy). Scan slowly and allow extra time for surface detection."
    }

    // MARK: - Private

    private let sessionManager: ARSessionManager
    private var hasStartedScanning = false
    private var instructionDismissTask: Task<Void, Never>?

    // MARK: - Init

    init(sessionManager: ARSessionManager? = nil) {
        let manager = sessionManager ?? ARSessionManager()
        self.sessionManager = manager
        self.deviceCapability = manager.deviceCapability
        self.cameraPermission = ARSessionManager.cameraAuthorizationStatus()

        manager.onStateChange = { [weak self] state in
            self?.sessionState = state
        }

        manager.onSurfaceDetected = { [weak self] surfaces in
            self?.detectedSurfaces = surfaces
        }
    }

    // MARK: - Actions

    /// Starts the AR scanning session after checking camera permission.
    func startScan() async {
        errorMessage = nil

        // Check camera permission
        let permission = ARSessionManager.cameraAuthorizationStatus()
        cameraPermission = permission

        switch permission {
        case .authorized:
            break
        case .notDetermined:
            sessionState = .waitingForPermission
            let result = await sessionManager.requestCameraPermission()
            cameraPermission = result
            if result != .authorized {
                errorMessage = "Camera access is required for AR scanning. Please enable it in Settings."
                sessionState = .idle
                return
            }
        case .denied, .restricted:
            errorMessage = "Camera access is required for AR scanning. Please enable it in Settings."
            sessionState = .idle
            return
        }

        // Start session
        sessionManager.startSession()
        hasStartedScanning = true

        // Auto-dismiss instructions after 5 seconds
        instructionDismissTask?.cancel()
        instructionDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled {
                hasStartedScanning = true
            }
        }
    }

    /// Stops the AR scanning session.
    func stopScan() {
        instructionDismissTask?.cancel()
        instructionDismissTask = nil
        sessionManager.stopSession()
        hasStartedScanning = false
    }

    /// Pauses the AR scanning session.
    func pauseScan() {
        sessionManager.pauseSession()
    }

    /// Provides the ARSessionManager for the UIViewRepresentable wrapper.
    var arSessionManagerForView: ARSessionManager {
        sessionManager
    }
}
