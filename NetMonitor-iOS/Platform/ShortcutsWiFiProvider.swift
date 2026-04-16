import Foundation
import UIKit
import NetMonitorCore

// MARK: - ShortcutsWiFiReading

/// Raw data returned by the "Save Wi-Fi Reading to NetMonitor" AppIntent.
struct ShortcutsWiFiReading: Codable {
    let ssid: String
    let bssid: String
    let rssi: Int           // dBm
    let noise: Int          // dBm
    let channel: Int
    let txRate: Double      // Mbps
    let rxRate: Double      // Mbps
    let wifiStandard: String?
    let timestamp: Date
}

// MARK: - ShortcutsWiFiProvider

/// Bridges the "Save Wi-Fi Reading to NetMonitor" AppIntent to in-app callers.
///
/// The companion Shortcut now runs two actions:
///   1. "Get Network Details" (built-in)
///   2. "Save Wi-Fi Reading to NetMonitor" (our AppIntent)
///
/// The AppIntent calls ``WiFiReadingBridge.shared.publish(_:)`` in-process,
/// which resolves the continuation immediately. A fallback App Group file read
/// handles the cold-launch edge case.
///
/// See `docs/iOS-WiFi-Heatmap-Spec.md` for design details.
@MainActor
@Observable
final class ShortcutsWiFiProvider: @unchecked Sendable {

    /// Whether the companion Shortcut appears to be installed and working.
    private(set) var isAvailable: Bool = false

    /// App Group identifier for the shared container.
    private static let appGroupID = "group.com.blakemiller.netmonitor"

    /// Filename written as a backup by ``WiFiReadingBridge.writeBackup(_:)``.
    private static let readingFilename = "wifi-reading.json"

    /// Maximum time to wait for the Shortcut round-trip.
    static let defaultTimeout: TimeInterval = 10.0

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Triggers the companion Shortcut and waits for Wi-Fi data.
    ///
    /// Returns `nil` if the shortcut is not installed, times out, or fails.
    /// Timeout defaults to 10 seconds — the 9-action shortcut plus app-switch
    /// overhead can take 2–5 s on a fresh run, so 10 s gives a safety margin.
    /// Success path resolves immediately when the bridge publishes.
    func fetchWiFiSignal(timeout: TimeInterval = ShortcutsWiFiProvider.defaultTimeout) async throws -> ShortcutsWiFiReading? {
        // Clear any stale reading from the shared container
        clearSharedReading()

        // Build the Shortcuts URL — no x-success callback needed; the AppIntent
        // handles the return trip via openAppWhenRun = true.
        guard let shortcutURL = URL(string: "shortcuts://x-callback-url/run-shortcut?name=Wi-Fi%20to%20NetMonitor") else {
            return nil
        }

        // Check if Shortcuts URL scheme can be opened
        guard UIApplication.shared.canOpenURL(shortcutURL) else {
            isAvailable = false
            return nil
        }

        // Open the Shortcut
        let opened = await UIApplication.shared.open(shortcutURL)
        guard opened else {
            isAvailable = false
            return nil
        }

        // Await the in-process bridge. The AppIntent's perform() will call
        // WiFiReadingBridge.shared.publish(_:) which resolves this immediately.
        let reading = await WiFiReadingBridge.shared.waitForReading(timeout: timeout)

        if let reading {
            isAvailable = true
            return reading
        }

        // Cold-launch fallback: if the app was launched by the intent before
        // waitForReading was called, the in-memory bridge had no listener.
        // The intent still wrote to the App Group file, so try that.
        let fallback = readSharedReading()
        if fallback != nil {
            isAvailable = true
        }
        return fallback
    }

    /// Checks if the companion Shortcut appears to be installed by testing
    /// whether the Shortcuts URL scheme can be opened.
    func checkAvailability() async -> Bool {
        guard let url = URL(string: "shortcuts://") else { return false }
        let canOpen = UIApplication.shared.canOpenURL(url)
        isAvailable = canOpen
        return canOpen
    }

    // MARK: - WiFiInfo Conversion

    /// Converts a Shortcuts reading to the shared ``WiFiInfo`` model.
    static func wifiInfo(from reading: ShortcutsWiFiReading) -> WiFiInfo {
        let band = bandFromChannel(reading.channel)
        let frequency = frequencyFromChannel(reading.channel)

        return WiFiInfo(
            ssid: reading.ssid,
            bssid: reading.bssid,
            signalStrength: rssiToPercent(reading.rssi),
            signalDBm: reading.rssi,
            channel: reading.channel,
            frequency: frequency.map { "\(Int($0)) MHz" },
            band: band,
            noiseLevel: reading.noise,
            linkSpeed: reading.txRate
        )
    }

    // MARK: - Shared Container I/O

    private func readSharedReading() -> ShortcutsWiFiReading? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) else { return nil }

        let fileURL = containerURL.appendingPathComponent(Self.readingFilename)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ShortcutsWiFiReading.self, from: data)
    }

    private func clearSharedReading() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) else { return }

        let fileURL = containerURL.appendingPathComponent(Self.readingFilename)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Channel Helpers

    private static func bandFromChannel(_ channel: Int) -> WiFiBand? {
        switch channel {
        case 1...14: return .band2_4GHz
        case 36...177: return .band5GHz
        case 233...254: return .band6GHz  // UNII-5 to UNII-8
        default: return nil
        }
    }

    private static func frequencyFromChannel(_ channel: Int) -> Double? {
        switch channel {
        case 1...13:
            return 2412 + Double(channel - 1) * 5
        case 14:
            return 2484
        case 36...177:
            return 5000 + Double(channel) * 5
        default:
            return nil
        }
    }

    private static func rssiToPercent(_ rssi: Int) -> Int {
        // Map -100..-30 dBm to 0..100%
        let clamped = max(-100, min(-30, rssi))
        return Int(Double(clamped + 100) / 70.0 * 100.0)
    }
}
