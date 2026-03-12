import CoreWLAN
import Foundation
import NetMonitorCore

// MARK: - NearbyAP

struct NearbyAP: Identifiable, Sendable {
    let id: String // BSSID
    let ssid: String
    let bssid: String
    let rssi: Int
    let channel: Int
    let band: WiFiBand?
    let noise: Int?
}

// MARK: - WiFiHeatmapService

/// CoreWLAN wrapper providing live signal data and nearby AP scanning for the heatmap tool.
/// All reads are synchronous via CWWiFiClient — safe to call from @MainActor.
@MainActor
final class WiFiHeatmapService {

    private let interfaceName: String?

    init() {
        interfaceName = CWWiFiClient.shared().interface()?.interfaceName
    }

    /// Returns a fresh CWInterface each call to avoid cached RSSI values
    private var iface: CWInterface? {
        guard let name = interfaceName else { return nil }
        return CWInterface(name: name)
    }

    // MARK: - Live Signal

    struct SignalSnapshot: Sendable {
        let rssi: Int
        let noiseFloor: Int?
        let snr: Int?
        let ssid: String?
        let bssid: String?
        let channel: Int?
        let band: WiFiBand?
        let linkSpeed: Int?
        let frequency: Double?
    }

    func currentSignal() -> SignalSnapshot? {
        guard let iface, iface.powerOn() else { return nil }

        let rssi = iface.rssiValue()
        let noise = iface.noiseMeasurement()
        let snr = (noise != 0) ? rssi - noise : nil
        let channel = iface.wlanChannel()?.channelNumber
        let band = bandFromChannel(iface.wlanChannel())
        let txRate = iface.transmitRate()
        let linkSpeed = txRate > 0 ? Int(txRate) : nil
        let frequency = channel.map { Self.channelToFrequencyMHz($0) }

        return SignalSnapshot(
            rssi: rssi,
            noiseFloor: noise != 0 ? noise : nil,
            snr: snr,
            ssid: iface.ssid(),
            bssid: iface.bssid(),
            channel: channel,
            band: band,
            linkSpeed: linkSpeed,
            frequency: frequency
        )
    }

    // MARK: - Nearby AP Scan

    func scanForNearbyAPs() -> [NearbyAP] {
        guard let iface else { return [] }
        do {
            let networks = try iface.scanForNetworks(withName: nil)
            return networks.compactMap { network in
                guard let bssid = network.bssid,
                      let wlanChannel = network.wlanChannel
                else { return nil }
                return NearbyAP(
                    id: bssid,
                    ssid: network.ssid ?? "(Hidden)",
                    bssid: bssid,
                    rssi: network.rssiValue,
                    channel: wlanChannel.channelNumber,
                    band: bandFromChannel(wlanChannel),
                    noise: network.noiseMeasurement != 0 ? network.noiseMeasurement : nil
                )
            }
            .sorted { $0.rssi > $1.rssi }
        } catch {
            return []
        }
    }

    // MARK: - Private

    private func bandFromChannel(_ channel: CWChannel?) -> WiFiBand? {
        guard let channel else { return nil }
        switch channel.channelBand {
        case .band2GHz: return .band2_4GHz
        case .band5GHz: return .band5GHz
        case .band6GHz: return .band6GHz
        @unknown default: return nil
        }
    }

    private static func channelToFrequencyMHz(_ channel: Int) -> Double {
        switch channel {
        case 1...13: return Double(2412 + (channel - 1) * 5)
        case 14: return 2484
        case 36...177: return Double(5000 + channel * 5)
        default: return 0
        }
    }
}
