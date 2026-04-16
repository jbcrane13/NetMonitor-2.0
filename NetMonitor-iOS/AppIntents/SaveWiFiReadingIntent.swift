import AppIntents
import Foundation

struct SaveWiFiReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Wi-Fi Reading to NetMonitor"
    // periphery:ignore
    static let description = IntentDescription(
        "Passes Wi-Fi Get Network Details values to NetMonitor for heatmap surveys. Chain this action after 'Get Network Details' in a Shortcut."
    )
    nonisolated(unsafe) static var openAppWhenRun: Bool = true

    @Parameter(title: "Network Name (SSID)") var ssid: String
    @Parameter(title: "BSSID") var bssid: String?
    @Parameter(title: "Signal Strength (RSSI, dBm)") var rssi: Int
    @Parameter(title: "Noise (dBm)") var noise: Int?
    @Parameter(title: "Channel") var channel: Int
    @Parameter(title: "TX Rate (Mbps)") var txRate: Double?
    @Parameter(title: "RX Rate (Mbps)") var rxRate: Double?
    @Parameter(title: "Wi-Fi Standard") var wifiStandard: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        let reading = ShortcutsWiFiReading(
            ssid: ssid,
            bssid: bssid ?? "",
            rssi: rssi,
            noise: noise ?? 0,
            channel: channel,
            txRate: txRate ?? 0,
            rxRate: rxRate ?? 0,
            wifiStandard: wifiStandard,
            timestamp: Date()
        )
        WiFiReadingBridge.shared.publish(reading)
        WiFiReadingBridge.writeBackup(reading)
        return .result()
    }
}
