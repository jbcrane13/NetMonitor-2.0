import Foundation
import SwiftUI
import NetMonitorCore
import CoreLocation
#if os(iOS)
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
#endif

/// ViewModel for AR continuous WiFi heatmap surveying.
///
/// Polls signal strength and AR camera position on a 1-second interval.
/// When the device has moved at least `ARHeatmapSession.distanceGate` meters
/// since the last recording, a data point is automatically captured and a
/// color-coded sphere placed in the AR scene.
///
/// On completion, world XZ coordinates are normalized to 0–1 range so the
/// result can be rendered by the existing `HeatmapCanvasView`.
@MainActor
@Observable
final class ARHeatmapSurveyViewModel {

    // MARK: - Public State

    private(set) var isScanning = false
    var signalDBm: Int = -65
    var signalQuality: Double = 0.5
    private(set) var ssid: String?
    private(set) var pointCount: Int = 0
    private(set) var statusMessage = "Tap Start to begin scanning"
    var errorMessage: String?
    /// Normalized heatmap data points for the live 2D overlay canvas.
    private(set) var liveHeatmapPoints: [HeatmapDataPoint] = []

    let arSession: ARHeatmapSession
    private(set) var locationDenied = false

    // MARK: - Private State

    /// Raw recorded positions in AR world XZ coordinates.
    private var worldPoints: [(x: Float, z: Float, signalStrength: Int, timestamp: Date)] = []
    /// Last recorded XZ position for distance gating.
    private var lastRecordedPosition: SIMD2<Float>?
    private var scanTask: Task<Void, Never>?
    private let locationDelegate = ARHeatmapLocationDelegate()

    // MARK: - Init

    init(arSession: ARHeatmapSession? = nil) {
        self.arSession = arSession ?? ARHeatmapSession()
    }

    // MARK: - Lifecycle

    func startScanning() {
        guard !isScanning else { return }

        // NEHotspotNetwork.fetchCurrent requires location authorization
        let status = locationDelegate.manager.authorizationStatus
        if status == .notDetermined {
            locationDelegate.manager.requestWhenInUseAuthorization()
            statusMessage = "Grant location access to read WiFi signal"
            locationDelegate.onAuthorized = { [weak self] in
                Task { @MainActor in self?.beginScanning() }
            }
            locationDelegate.onDenied = { [weak self] in
                Task { @MainActor in
                    self?.locationDenied = true
                    self?.errorMessage = "Location access required for WiFi signal reading"
                    self?.statusMessage = "Enable location in Settings > Privacy > Location Services"
                }
            }
            return
        } else if status == .denied || status == .restricted {
            locationDenied = true
            errorMessage = "Location access denied — enable in Settings > Privacy > Location Services"
            return
        }

        beginScanning()
    }

    private func beginScanning() {
        locationDenied = false
        isScanning = true
        worldPoints = []
        liveHeatmapPoints = []
        lastRecordedPosition = nil
        pointCount = 0
        errorMessage = nil
        statusMessage = "Walk around to map your WiFi coverage"

        arSession.startSession()

        scanTask = Task {
            while !Task.isCancelled {
                await sampleSignalAndPosition()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopScanning() {
        guard isScanning else { return }
        isScanning = false
        scanTask?.cancel()
        scanTask = nil
        arSession.stopSession()

        if worldPoints.isEmpty {
            statusMessage = "No data recorded"
        } else {
            statusMessage = "Scan complete — \(worldPoints.count) measurements"
        }
    }

    /// Builds a `HeatmapSurvey` from the recorded world points, normalizing
    /// XZ coordinates to 0–1 range for the existing heatmap renderer.
    func buildSurvey(name: String? = nil) -> HeatmapSurvey? {
        let normalized = normalizePoints()
        guard !normalized.isEmpty else { return nil }
        return HeatmapSurvey(
            name: name ?? "AR Scan",
            mode: .arContinuous,
            dataPoints: normalized
        )
    }

    // MARK: - Display Helpers

    var signalColor: Color {
        if signalDBm > -50 { return .green }
        if signalDBm > -70 { return .yellow }
        return .red
    }

    var signalLabel: String {
        if signalDBm > -50 { return "Excellent" }
        if signalDBm > -70 { return "Good" }
        if signalDBm > -85 { return "Fair" }
        return "Poor"
    }

    var signalText: String {
        isScanning ? "\(signalDBm) dBm" : "--"
    }

    // MARK: - Private

    private func sampleSignalAndPosition() async {
        await refreshSignal()

        guard let position = arSession.currentXZPosition else { return }

        let shouldRecord: Bool
        if let lastPos = lastRecordedPosition {
            let delta = position - lastPos
            let dist = sqrt(delta.x * delta.x + delta.y * delta.y)
            shouldRecord = dist >= ARHeatmapSession.distanceGate
        } else {
            // First point — always record
            shouldRecord = true
        }

        if shouldRecord {
            worldPoints.append((x: position.x, z: position.y, signalStrength: signalDBm, timestamp: Date()))
            lastRecordedPosition = position
            pointCount = worldPoints.count
            arSession.placeSignalSphere(signalDBm: signalDBm)

            // Update the live 2D heatmap overlay in real time
            liveHeatmapPoints = normalizePoints()

            let level = SignalLevel.from(rssi: signalDBm)
            statusMessage = "\(signalDBm) dBm (\(level.label)) — \(worldPoints.count) points"
        }
    }

    private func refreshSignal() async {
        // Use WiFiInfoService pattern: NEHotspotNetwork with retry + legacy CNCopy fallback.
        // This matches how the dashboard reads WiFi and avoids the 0.0 / -100dBm bug.
        #if targetEnvironment(simulator)
        signalQuality = 0.65
        signalDBm = -55
        ssid = "Simulator WiFi"
        #elseif os(iOS)
        // Attempt 1: modern API
        var network = await NEHotspotNetwork.fetchCurrent()
        if network == nil {
            // Retry once after short delay (same pattern as WiFiInfoService)
            try? await Task.sleep(for: .milliseconds(300))
            network = await NEHotspotNetwork.fetchCurrent()
        }

        if let network, network.signalStrength > 0 {
            errorMessage = nil
            signalQuality = max(0, min(1, network.signalStrength))
            signalDBm = Int(-100.0 + signalQuality * 70.0)
            ssid = network.ssid
        } else {
            // Legacy fallback — CNCopyCurrentNetworkInfo gives SSID but no signal
            if let interfaces = CNCopySupportedInterfaces() as? [String],
               let iface = interfaces.first,
               let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: Any],
               let legacySSID = info[kCNNetworkInfoKeySSID as String] as? String {
                ssid = legacySSID
            } else if errorMessage == nil {
                errorMessage = "WiFi signal unavailable — ensure WiFi is connected"
            }
        }
        #endif
    }

    /// Normalize world XZ coordinates to 0–1 range based on bounding box.
    func normalizePoints() -> [HeatmapDataPoint] {
        guard !worldPoints.isEmpty else { return [] }

        let xs = worldPoints.map(\.x)
        let zs = worldPoints.map(\.z)
        guard let xMin = xs.min(), let xMax = xs.max(),
              let zMin = zs.min(), let zMax = zs.max() else { return [] }
        let rangeX = xMax - xMin
        let rangeZ = zMax - zMin

        return worldPoints.map { pt in
            let nx = rangeX > 0.001 ? Double((pt.x - xMin) / rangeX) : 0.5
            let ny = rangeZ > 0.001 ? Double((pt.z - zMin) / rangeZ) : 0.5
            return HeatmapDataPoint(x: nx, y: ny, signalStrength: pt.signalStrength, timestamp: pt.timestamp)
        }
    }
}

// MARK: - Location Authorization Helper

private final class ARHeatmapLocationDelegate: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var onAuthorized: (() -> Void)?
    var onDenied: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            onAuthorized?()
            onAuthorized = nil
            onDenied = nil
        case .denied, .restricted:
            onDenied?()
            onAuthorized = nil
            onDenied = nil
        default:
            break
        }
    }
}
