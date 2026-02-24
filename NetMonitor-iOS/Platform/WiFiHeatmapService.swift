import Foundation
import NetMonitorCore

/// Platform implementation of WiFiHeatmapServiceProtocol.
/// Stores recorded data points in memory for the current survey session.
final class WiFiHeatmapService: WiFiHeatmapServiceProtocol, @unchecked Sendable {
    private var dataPoints: [HeatmapDataPoint] = []
    private var isActive = false

    func startSurvey() {
        isActive = true
        dataPoints = []
    }

    func recordDataPoint(signalStrength: Int, x: Double, y: Double) {
        guard isActive else { return }
        dataPoints.append(HeatmapDataPoint(x: x, y: y, signalStrength: signalStrength))
    }

    func getSurveyData() -> [HeatmapDataPoint] {
        dataPoints
    }

    func stopSurvey() {
        isActive = false
    }
}
