import Foundation
import NetMonitorCore

struct WiFiSignalSample: Sendable, Equatable {
    let dbm: Int?
    let ssid: String?
    let bssid: String?
}

@MainActor
protocol WiFiSignalSampling {
    func currentSample() async -> WiFiSignalSample
}

@MainActor
final class WiFiSignalSampler: WiFiSignalSampling {
    private let wifiService: any WiFiInfoServiceProtocol
    private var lastKnownDBm: Int?
    private var lastKnownSSID: String?
    private var lastKnownBSSID: String?

    init(wifiService: any WiFiInfoServiceProtocol = WiFiInfoService()) {
        self.wifiService = wifiService
    }

    func currentSample() async -> WiFiSignalSample {
        let wifiInfo = await wifiService.fetchCurrentWiFi()
        let dbm = wifiInfo.flatMap(Self.resolveDBm(from:))

        // Only carry forward last-known dBm when the service returns nil transiently
        // while we're still connected (ssid cached) — avoids a false "good signal"
        // flash on a dead connection.
        // Return nil when there is genuinely no signal information so callers can
        // show the "estimated" indicator rather than a misleading fallback value.
        let resolvedDBm: Int?
        if let dbm {
            resolvedDBm = dbm
        } else if wifiInfo?.ssid != nil || lastKnownSSID != nil, let last = lastKnownDBm {
            // Transient read failure while still apparently connected — reuse last known.
            resolvedDBm = last
        } else {
            // Cold start or no WiFi: signal is genuinely unknown.
            resolvedDBm = nil
        }

        lastKnownDBm = resolvedDBm
        if let ssid = wifiInfo?.ssid {
            lastKnownSSID = ssid
        }
        if let bssid = wifiInfo?.bssid {
            lastKnownBSSID = bssid
        }

        return WiFiSignalSample(
            dbm: resolvedDBm,
            ssid: wifiInfo?.ssid ?? lastKnownSSID,
            bssid: wifiInfo?.bssid ?? lastKnownBSSID
        )
    }

    private static func resolveDBm(from wifiInfo: WiFiInfo) -> Int? {
        if let dbm = wifiInfo.signalDBm {
            return dbm
        }

        if let percent = wifiInfo.signalStrength {
            let clamped = max(0, min(100, percent))
            return Int(-100.0 + (Double(clamped) / 100.0 * 70.0))
        }

        return nil
    }
}
