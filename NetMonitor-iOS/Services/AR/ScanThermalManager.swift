import Foundation
import os

// MARK: - ScanThermalState

/// Simplified thermal state for the continuous scan pipeline.
enum ScanThermalState: Sendable, Equatable {
    /// Normal operation — no thermal concern.
    case nominal
    /// Elevated — device is warming. Reduce non-essential work.
    case elevated
    /// Serious — reduce mesh updates, lower render rate.
    case serious
    /// Critical — auto-pause all pipelines immediately.
    case critical
}

// MARK: - ScanThermalAction

/// Recommended action based on thermal state.
enum ScanThermalAction: Sendable, Equatable {
    /// Continue scanning at full capacity.
    case continueNormal
    /// Reduce mesh processing — skip every other mesh anchor update.
    case reduceMesh
    /// Auto-pause the scan to cool down.
    case autoPause
}

// MARK: - ScanThermalManager

/// Monitors `ProcessInfo.thermalState` and provides thermal management
/// decisions for the Phase 3 continuous scan pipeline.
///
/// Thermal policy:
/// - `.nominal` / `.fair` → continue normally (CPU <60%, GPU <40%)
/// - `.serious` → reduce mesh updates, pause mesh processing, continue Wi-Fi
/// - `.critical` → auto-pause all pipelines with user notification
///
/// The manager observes `thermalStateDidChangeNotification` and publishes
/// state changes via a callback. The ViewModel polls or observes the
/// recommended action and responds accordingly.
@MainActor
final class ScanThermalManager {

    // MARK: - State

    /// Current thermal state mapped from ProcessInfo.
    private(set) var thermalState: ScanThermalState = .nominal

    /// Whether the scan was auto-paused due to critical thermal state.
    private(set) var wasAutoPaused = false

    /// Callback invoked when thermal state changes.
    var onStateChange: ((ScanThermalState) -> Void)?

    /// Callback invoked when an auto-pause is triggered.
    var onAutoPause: (() -> Void)?

    // MARK: - Private

    private var observer: (any NSObjectProtocol)?

    // MARK: - Init

    init() {
        thermalState = Self.mapThermalState(ProcessInfo.processInfo.thermalState)
        startMonitoring()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleThermalChange()
            }
        }
    }

    /// Removes the thermal state observer. Call when the manager is no longer needed.
    func stopMonitoring() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    private func handleThermalChange() {
        let newState = Self.mapThermalState(ProcessInfo.processInfo.thermalState)
        let oldState = thermalState
        thermalState = newState

        if newState != oldState {
            onStateChange?(newState)
            Logger.heatmap.info(
                "Thermal state changed: \(String(describing: oldState)) → \(String(describing: newState))"
            )

            if newState == .critical {
                wasAutoPaused = true
                onAutoPause?()
                Logger.heatmap.warning("Critical thermal state — auto-pausing continuous scan")
            }
        }
    }

    // MARK: - Recommended Action

    /// Returns the recommended action for the current thermal state.
    var recommendedAction: ScanThermalAction {
        switch thermalState {
        case .nominal, .elevated:
            return .continueNormal
        case .serious:
            return .reduceMesh
        case .critical:
            return .autoPause
        }
    }

    /// Whether mesh processing should be skipped this tick (for `.serious` throttling).
    /// Alternates between processing and skipping to reduce CPU load by ~50%.
    private var meshSkipCounter = 0

    func shouldProcessMesh() -> Bool {
        switch thermalState {
        case .nominal, .elevated:
            return true
        case .serious:
            meshSkipCounter += 1
            return meshSkipCounter % 2 == 0
        case .critical:
            return false
        }
    }

    /// Resets auto-pause state after user manually resumes.
    func resetAutoPause() {
        wasAutoPaused = false
    }

    // MARK: - State Mapping

    static func mapThermalState(_ state: ProcessInfo.ThermalState) -> ScanThermalState {
        switch state {
        case .nominal:
            return .nominal
        case .fair:
            return .elevated
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .nominal
        }
    }
}
