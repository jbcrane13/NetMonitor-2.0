import Foundation
import SwiftUI
import NetMonitorCore
#if os(iOS)
import NetworkExtension
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

    let arSession: ARHeatmapSession

    // MARK: - Private State

    /// Raw recorded positions in AR world XZ coordinates.
    private var worldPoints: [(x: Float, z: Float, signalStrength: Int, timestamp: Date)] = []
    /// Last recorded XZ position for distance gating.
    private var lastRecordedPosition: SIMD2<Float>?
    private var scanTask: Task<Void, Never>?

    // MARK: - Init

    init(arSession: ARHeatmapSession? = nil) {
        self.arSession = arSession ?? ARHeatmapSession()
    }

    // MARK: - Lifecycle

    func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        worldPoints = []
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

            let level = SignalLevel.from(rssi: signalDBm)
            statusMessage = "\(signalDBm) dBm (\(level.label)) — \(worldPoints.count) points"
        }
    }

    private func refreshSignal() async {
        #if targetEnvironment(simulator)
        applySignalStrength(0.65, ssid: "Simulator WiFi")
        #elseif os(iOS)
        guard let network = await NEHotspotNetwork.fetchCurrent() else {
            if errorMessage == nil {
                errorMessage = "Could not read WiFi signal. Check location permission."
            }
            return
        }
        errorMessage = nil
        applySignalStrength(network.signalStrength, ssid: network.ssid)
        #endif
    }

    private func applySignalStrength(_ strength: Double, ssid: String?) {
        signalQuality = max(0, min(1, strength))
        signalDBm = Int(-100.0 + signalQuality * 70.0)
        self.ssid = ssid
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
