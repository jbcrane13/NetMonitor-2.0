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
    private static let defaultFallbackDBm = -70

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
        let connectedFallbackDBm: Int? = wifiInfo?.ssid != nil ? -70 : nil
        let resolvedDBm = dbm ?? lastKnownDBm ?? connectedFallbackDBm ?? Self.defaultFallbackDBm

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
