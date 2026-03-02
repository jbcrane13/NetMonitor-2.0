import Foundation
import SwiftUI
import NetMonitorCore
import CoreLocation
#if os(iOS)
import NetworkExtension
import SystemConfiguration.CaptiveNetwork
#endif

// MARK: - ARContinuousHeatmapViewModel

/// Drives the AR continuous heatmap scanning mode.
///
/// Manages a 32×32 grid of RSSI values painted cell-by-cell as the user walks.
/// Signal is polled every second; a 30 cm distance gate prevents duplicate readings.
/// On completion, world XZ coordinates are normalised to 0–1 for HeatmapSurvey.
@MainActor
@Observable
final class ARContinuousHeatmapViewModel {

    // MARK: - Constants

    static let gridSize = 32
    static let texturePx = 1024     // 32 px per cell
    static let cellPx = texturePx / gridSize   // 32 px

    // MARK: - Public State (var so tests can inject)

    var isScanning = false
    var floorDetected = false
    var signalDBm: Int = -65
    var ssid: String?
    var bssid: String?
    var band: String?
    var pointCount: Int = 0
    var errorMessage: String?
    var statusMessage = "Initializing AR session."

    /// 32×32 grid — nil means unvisited, Int = RSSI dBm at that cell.
    var gridState: [[Int?]] = Array(
        repeating: Array(repeating: nil, count: ARContinuousHeatmapViewModel.gridSize),
        count: ARContinuousHeatmapViewModel.gridSize
    )
    /// The grid cell currently under the camera (for drawing the position ring).
    private(set) var currentCell: (col: Int, row: Int)?

    // MARK: - Private

    let session: ARContinuousHeatmapSession
    private var worldPoints: [(x: Float, z: Float, signalStrength: Int, timestamp: Date)] = []
    private var lastRecordedPosition: SIMD3<Float>?
    private var scanTask: Task<Void, Never>?
    private let locationDelegate = ARHeatmapLocationDelegate()

    // MARK: - Init

    init(session: ARContinuousHeatmapSession? = nil) {
        self.session = session ?? ARContinuousHeatmapSession()
    }

    // MARK: - Lifecycle

    func startScanning() {
        guard !isScanning else { return }

        #if targetEnvironment(simulator)
        // Skip location check on simulator — NEHotspotNetwork uses mock values.
        beginScanning()
        return
        #else
        let status = locationDelegate.manager.authorizationStatus
        if status == .notDetermined {
            locationDelegate.manager.requestWhenInUseAuthorization()
            statusMessage = "Grant location access to read WiFi signal"
            locationDelegate.onAuthorized = { [weak self] in
                Task { @MainActor in self?.beginScanning() }
            }
            locationDelegate.onDenied = { [weak self] in
                Task { @MainActor in
                    self?.errorMessage = "Location access required for WiFi signal reading"
                }
            }
            return
        } else if status == .denied || status == .restricted {
            errorMessage = "Location access denied — enable in Settings > Privacy > Location Services"
            return
        }

        beginScanning()
        #endif
    }

    private func beginScanning() {
        isScanning = true
        floorDetected = false
        worldPoints = []
        gridState = Array(repeating: Array(repeating: nil, count: Self.gridSize), count: Self.gridSize)
        currentCell = nil
        lastRecordedPosition = nil
        pointCount = 0
        errorMessage = nil
        statusMessage = "Initializing AR session."

        session.onFloorDetected = { [weak self] in
            Task { @MainActor in
                self?.floorDetected = true
                self?.statusMessage = "Walk around to map coverage"
            }
        }

        session.startSession()

        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleTick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopScanning() {
        guard isScanning else { return }
        isScanning = false
        scanTask?.cancel()
        scanTask = nil
        session.stopSession()
        statusMessage = worldPoints.isEmpty ? "No data recorded" : "Scan complete — \(worldPoints.count) measurements"
    }

    // MARK: - Survey Output

    /// Build a `HeatmapSurvey` from the recorded world points, normalising XZ to 0–1.
    func buildSurvey(name: String? = nil) -> HeatmapSurvey? {
        let normalised = normalisePoints()
        guard !normalised.isEmpty else { return nil }
        return HeatmapSurvey(name: name ?? "AR Scan", mode: .arContinuous, dataPoints: normalised)
    }

    // MARK: - Grid Texture

    /// Render `gridState` into a 1024×1024 UIImage for the floor plane texture.
    func renderGridTexture() -> UIImage {
        let size = CGFloat(Self.texturePx)
        let cellSize = CGFloat(Self.cellPx)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // Background — fully transparent
            cgCtx.clear(CGRect(x: 0, y: 0, width: size, height: size))

            // Paint visited cells
            for row in 0..<Self.gridSize {
                for col in 0..<Self.gridSize {
                    guard let rssi = gridState[row][col] else { continue }
                    let rgb = HeatmapRenderer.colorComponents(rssi: rssi, scheme: .signal)
                    let color = UIColor(red: CGFloat(rgb.r) / 255,
                                       green: CGFloat(rgb.g) / 255,
                                       blue: CGFloat(rgb.b) / 255,
                                       alpha: 0.85)
                    cgCtx.setFillColor(color.cgColor)
                    let rect = CGRect(x: CGFloat(col) * cellSize,
                                     y: CGFloat(row) * cellSize,
                                     width: cellSize, height: cellSize)
                    cgCtx.fill(rect)
                }
            }

            // Grid lines (subtle)
            cgCtx.setStrokeColor(UIColor.white.withAlphaComponent(0.12).cgColor)
            cgCtx.setLineWidth(0.5)
            for i in 0...Self.gridSize {
                let x = CGFloat(i) * cellSize
                cgCtx.move(to: CGPoint(x: x, y: 0))
                cgCtx.addLine(to: CGPoint(x: x, y: size))
                let y = CGFloat(i) * cellSize
                cgCtx.move(to: CGPoint(x: 0, y: y))
                cgCtx.addLine(to: CGPoint(x: size, y: y))
            }
            cgCtx.strokePath()

            // Current position ring
            if let cell = currentCell {
                let cx = CGFloat(cell.col) * cellSize + cellSize / 2
                let cy = CGFloat(cell.row) * cellSize + cellSize / 2
                let radius = cellSize * 0.4
                let ring = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                cgCtx.setStrokeColor(UIColor.white.cgColor)
                cgCtx.setLineWidth(2.0)
                cgCtx.strokeEllipse(in: ring)
                // Inner fill
                cgCtx.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
                let inner = ring.insetBy(dx: radius * 0.6, dy: radius * 0.6)
                cgCtx.fillEllipse(in: inner)
            }
        }
    }

    // MARK: - Display Helpers

    var signalColor: Color {
        if signalDBm > -50 { return .green }
        if signalDBm > -70 { return .yellow }
        return .red
    }

    var signalText: String {
        isScanning ? "\(signalDBm) dBm" : "--"
    }

    // MARK: - Internal helpers (accessible to tests)

    /// Inject a world point directly (test support).
    func injectWorldPoint(x: Float, z: Float, rssi: Int) {
        worldPoints.append((x: x, z: z, signalStrength: rssi, timestamp: Date()))
        pointCount = worldPoints.count
    }

    /// Set last recorded position (test support).
    func setLastPosition(_ position: SIMD3<Float>) {
        lastRecordedPosition = position
    }

    /// Returns true when the camera has moved more than `distanceGate` from last recorded position.
    func distanceExceeded(from position: SIMD3<Float>) -> Bool {
        guard let last = lastRecordedPosition else { return true }
        let delta = position - last
        return sqrt(delta.x * delta.x + delta.z * delta.z) >= ARContinuousHeatmapSession.distanceGate
    }

    // MARK: - Private

    private func sampleTick() async {
        await refreshSignal()

        guard let pos = session.currentWorldPosition else {
            if !floorDetected {
                statusMessage = "Detecting floor..."
            }
            return
        }

        // Update current cell for the position ring
        currentCell = session.worldToGridCell(gridSize: Self.gridSize)

        guard distanceExceeded(from: pos) else { return }
        lastRecordedPosition = pos

        // Record world point
        worldPoints.append((x: pos.x, z: pos.z, signalStrength: signalDBm, timestamp: Date()))
        pointCount = worldPoints.count

        // Paint grid cell
        if let cell = currentCell {
            gridState[cell.row][cell.col] = signalDBm
        }

        // Update AR plane texture
        let texture = renderGridTexture()
        session.updateGridTexture(texture)
    }

    private func refreshSignal() async {
        #if targetEnvironment(simulator)
        signalDBm = -55
        ssid = "Simulator WiFi"
        bssid = "AA:BB:CC:DD:EE:FF"
        band = "5 GHz"
        #elseif os(iOS)
        var network = await NEHotspotNetwork.fetchCurrent()
        if network == nil {
            try? await Task.sleep(for: .milliseconds(300))
            network = await NEHotspotNetwork.fetchCurrent()
        }

        if let network, network.signalStrength > 0 {
            errorMessage = nil
            let quality = max(0, min(1, network.signalStrength))
            signalDBm = Int(-100.0 + quality * 70.0)
            ssid = network.ssid
            bssid = network.bssid
        } else {
            if let interfaces = CNCopySupportedInterfaces() as? [String],
               let iface = interfaces.first,
               let info = CNCopyCurrentNetworkInfo(iface as CFString) as? [String: Any] {
                ssid = info[kCNNetworkInfoKeySSID as String] as? String
            } else if errorMessage == nil {
                errorMessage = "WiFi signal unavailable"
            }
        }
        #endif
    }

    private func normalisePoints() -> [HeatmapDataPoint] {
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

// MARK: - Location auth helper (reused from existing pattern)

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
