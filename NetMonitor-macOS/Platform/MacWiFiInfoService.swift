import CoreLocation
import CoreWLAN
import Foundation
import NetMonitorCore
import os

// MARK: - MacWiFiInfoService

/// macOS implementation of WiFiInfoServiceProtocol using CoreWLAN.
/// Provides RSSI, noise floor, channel, band, SSID, BSSID, and link speed
/// for use by WiFiMeasurementEngine during heatmap surveys.
@MainActor
@Observable
final class MacWiFiInfoService: WiFiInfoServiceProtocol {

    private(set) var currentWiFi: WiFiInfo?
    private(set) var isLocationAuthorized: Bool = true // macOS doesn't require location auth for CoreWLAN
    private(set) var authorizationStatus: CLAuthorizationStatus = .authorizedAlways // macOS CoreWLAN doesn't need location auth

    private let client = CWWiFiClient.shared()

    init() {
        refreshWiFiInfo()
    }

    func requestLocationPermission() {
        // macOS does not require location permission for CoreWLAN access
        isLocationAuthorized = true
    }

    func refreshWiFiInfo() {
        currentWiFi = readCurrentWiFi()
    }

    func fetchCurrentWiFi() async -> WiFiInfo? {
        readCurrentWiFi()
    }

    // MARK: - Private

    private func readCurrentWiFi() -> WiFiInfo? {
        guard let iface = client.interface(), iface.powerOn()
        else { return nil }

        let channelNumber = iface.wlanChannel()?.channelNumber

        // Determine band from channel
        let band: WiFiBand? = {
            guard let channel = iface.wlanChannel()
            else { return nil }
            switch channel.channelBand {
            case .band2GHz: return .band2_4GHz
            case .band5GHz: return .band5GHz
            case .band6GHz: return .band6GHz
            @unknown default: return nil
            }
        }()

        // Compute frequency in MHz from channel number
        let frequency: String? = channelNumber.map { String(Self.channelToFrequencyMHz($0)) }

        let transmitRate = iface.transmitRate()
        let linkSpeed: Double? = transmitRate > 0 ? transmitRate : nil

        return WiFiInfo(
            ssid: iface.ssid() ?? "Unknown",
            bssid: iface.bssid(),
            signalStrength: iface.rssiValue(),
            signalDBm: iface.rssiValue(),
            channel: channelNumber,
            frequency: frequency,
            band: band,
            noiseLevel: iface.noiseMeasurement(),
            linkSpeed: linkSpeed
        )
    }

    /// Converts a WiFi channel number to approximate frequency in MHz.
    private static func channelToFrequencyMHz(_ channel: Int) -> Int {
        switch channel {
        case 1 ... 13:
            // 2.4 GHz band: channel 1 = 2412 MHz, each +5 MHz
            return 2407 + (channel * 5)
        case 14:
            return 2484
        case 36 ... 177:
            // 5 GHz band: base 5000 MHz + channel * 5
            return 5000 + (channel * 5)
        default:
            // 6 GHz or unknown
            return 5000 + (channel * 5)
        }
    }
}
