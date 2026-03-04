import CoreWLAN
import Foundation
import os

// MARK: - CoreWLANServiceProtocol

/// Protocol for direct CoreWLAN access on macOS.
/// Provides live WiFi metrics: RSSI, noise floor, channel, band, link speed.
/// Used by the heatmap survey for the live RSSI toolbar badge.
@MainActor
protocol CoreWLANServiceProtocol: AnyObject {
    func currentRSSI() -> Int?
    func currentNoiseFloor() -> Int?
    func currentChannel() -> Int?
    func currentBand() -> String?
    func currentLinkSpeed() -> Int?
    func currentSSID() -> String?
    func currentBSSID() -> String?
}

// MARK: - CoreWLANService

/// macOS CoreWLAN service that reads WiFi metrics directly from the system.
/// All reads are synchronous (CWWiFiClient.shared() caches the interface).
@MainActor
final class CoreWLANService: CoreWLANServiceProtocol {

    private let client = CWWiFiClient.shared()

    private var interface: CWInterface? {
        client.interface()
    }

    func currentRSSI() -> Int? {
        guard let iface = interface, iface.powerOn()
        else { return nil }
        return iface.rssiValue()
    }

    func currentNoiseFloor() -> Int? {
        guard let iface = interface, iface.powerOn()
        else { return nil }
        return iface.noiseMeasurement()
    }

    func currentChannel() -> Int? {
        guard let iface = interface, iface.powerOn()
        else { return nil }
        return iface.wlanChannel()?.channelNumber
    }

    func currentBand() -> String? {
        guard let iface = interface, iface.powerOn(),
              let channel = iface.wlanChannel()
        else { return nil }
        switch channel.channelBand {
        case .band2GHz:
            return "2.4 GHz"
        case .band5GHz:
            return "5 GHz"
        case .band6GHz:
            return "6 GHz"
        @unknown default:
            return nil
        }
    }

    func currentLinkSpeed() -> Int? {
        guard let iface = interface, iface.powerOn()
        else { return nil }
        let rate = iface.transmitRate()
        return rate > 0 ? Int(rate) : nil
    }

    func currentSSID() -> String? {
        guard let iface = interface, iface.powerOn()
        else { return nil }
        return iface.ssid()
    }

    func currentBSSID() -> String? {
        guard let iface = interface, iface.powerOn()
        else { return nil }
        return iface.bssid()
    }
}
