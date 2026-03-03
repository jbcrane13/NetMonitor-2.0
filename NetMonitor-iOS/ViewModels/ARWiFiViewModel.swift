import Foundation
import SwiftUI
#if os(iOS)
import NetworkExtension
#endif

/// ViewModel for the AR WiFi Signal view.
///
/// Polls `NEHotspotNetwork.fetchCurrent()` for live signal strength and drives
/// the AR overlay. Signal strength is stored as an approximate dBm value mapped
/// from the 0–1 `signalStrength` property of `NEHotspotNetwork`.
@MainActor
@Observable
final class ARWiFiViewModel {
    // MARK: - Published State

    /// Current signal strength in approximate dBm (-100 to -30).
    var signalDBm: Int = -65
    /// Signal quality as a 0–1 fraction (used for progress bars / color thresholds).
    var signalQuality: Double = 0.5
    /// SSID of the connected network, if available.
    var ssid: String?
    /// BSSID of the connected access point, if available.
    var bssid: String?
    /// Whether the current device supports AR world tracking.
    var isARSupported: Bool
    /// Whether the AR session is actively running.
    var isSessionRunning: Bool = false
    /// Error or permission message, if any.
    var errorMessage: String?

    // MARK: - Dependencies

    let arSession: ARWiFiSession
    private var monitoringTask: Task<Void, Never>?

    // MARK: - Init

    init(arSession: ARWiFiSession? = nil) {
        let session = arSession ?? ARWiFiSession()
        self.arSession = session
        self.isARSupported = ARWiFiSession.isSupported
    }

    // MARK: - Actions

    func startSession() {
        guard isARSupported else {
            errorMessage = "AR is not supported on this device."
            return
        }
        arSession.startSession()
        isSessionRunning = true
        errorMessage = nil
        startSignalMonitoring()
    }

    func stopSession() {
        arSession.stopSession()
        isSessionRunning = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// Drop a signal-strength anchor at the current AR camera position.
    // periphery:ignore
    func placeAnchor() {
        arSession.placeSignalAnchor(signalDBm: signalDBm)
    }

    // MARK: - Signal Display Helpers

    /// Color representing the current signal strength.
    var signalColor: Color {
        if signalDBm > -50 { return .green }
        if signalDBm > -70 { return .yellow }
        return .red
    }

    /// Short human-readable signal quality label.
    var signalLabel: String {
        if signalDBm > -50 { return "Excellent" }
        if signalDBm > -70 { return "Good" }
        if signalDBm > -85 { return "Fair" }
        return "Poor"
    }

    // MARK: - Private

    private func startSignalMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = Task {
            while !Task.isCancelled {
                await refreshSignal()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshSignal() async {
        #if targetEnvironment(simulator)
        applySignalStrength(0.65, ssid: "Simulator WiFi", bssid: nil)
        #elseif os(iOS)
        guard let network = await NEHotspotNetwork.fetchCurrent() else {
            if errorMessage == nil {
                errorMessage = "Could not read WiFi signal. Check location permission."
            }
            return
        }
        errorMessage = nil
        applySignalStrength(network.signalStrength, ssid: network.ssid, bssid: network.bssid)
        #endif
    }

    /// Maps `NEHotspotNetwork.signalStrength` (0–1) to approximate dBm (-100 to -30).
    private func applySignalStrength(_ strength: Double, ssid: String?, bssid: String?) {
        signalQuality = max(0, min(1, strength))
        // Linear mapping: 0.0 → -100 dBm, 1.0 → -30 dBm
        signalDBm = Int(-100.0 + signalQuality * 70.0)
        self.ssid = ssid
        self.bssid = bssid
    }
}
