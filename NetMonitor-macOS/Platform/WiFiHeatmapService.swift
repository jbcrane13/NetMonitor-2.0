import Foundation
import CoreWLAN
import NetMonitorCore

// MARK: - WiFiHeatmapService (macOS)

/// macOS implementation of WiFiHeatmapServiceProtocol.
/// Reads RSSI from the primary Wi-Fi interface via CoreWLAN.
/// Falls back to simulated values when no interface is available.
///
/// Marked `@unchecked Sendable` because internal mutable state is
/// protected by an `NSLock` to satisfy Swift 6 strict-concurrency rules
/// while conforming to the protocol's `Sendable` requirement.
final class WiFiHeatmapService: WiFiHeatmapServiceProtocol, @unchecked Sendable {

    // MARK: - Private State

    private let lock = NSLock()
    private var _dataPoints: [HeatmapDataPoint] = []
    private var _isRunning = false

    // MARK: - WiFiHeatmapServiceProtocol

    func startSurvey() {
        lock.withLock {
            _isRunning = true
            _dataPoints = []
        }
    }

    func stopSurvey() {
        lock.withLock {
            _isRunning = false
        }
    }

    func recordDataPoint(signalStrength: Int, x: Double, y: Double) {
        let pt = HeatmapDataPoint(x: x, y: y, signalStrength: signalStrength, timestamp: Date())
        lock.withLock {
            _dataPoints.append(pt)
        }
    }

    func getSurveyData() -> [HeatmapDataPoint] {
        lock.withLock { _dataPoints }
    }

    // MARK: - Signal Reading (non-protocol helpers)

    /// Returns the current RSSI (in dBm) of the associated Wi-Fi network,
    /// or `nil` when no Wi-Fi interface is active or no network is associated.
    func currentRSSI() -> Int? {
        guard let iface = CWWiFiClient.shared().interface(),
              iface.serviceActive() else { return nil }
        return iface.rssiValue()
    }

    /// Returns a plausible simulated RSSI value for use in previews and
    /// on machines where no Wi-Fi interface is available.
    func simulatedRSSI() -> Int {
        Int.random(in: -80...(-45))
    }
}
