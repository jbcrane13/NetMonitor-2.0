import Foundation
import UIKit
import NetMonitorCore

// MARK: - ShortcutsWiFiReading

/// Raw data returned by the "Wi-Fi to NetMonitor" companion Shortcut
/// via the App Group shared container.
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

/// Bridges Apple Shortcuts "Get Network Details" action to the app via
/// URL scheme invocation and App Group shared container.
///
/// The companion Shortcut writes Wi-Fi data as JSON to the shared container,
/// then returns to the app via the `netmonitor://wifi-result` URL scheme.
/// This class orchestrates the round-trip and reads the result.
///
/// See `docs/iOS-WiFi-Heatmap-Spec.md` section 5 for design details.
@MainActor
@Observable
final class ShortcutsWiFiProvider: @unchecked Sendable {

    /// Whether the companion Shortcut appears to be installed and working.
    private(set) var isAvailable: Bool = false

    /// App Group identifier for the shared container.
    private static let appGroupID = "group.com.blakemiller.netmonitor"

    /// Filename written by the companion Shortcut.
    private static let readingFilename = "wifi-reading.json"

    /// Maximum time to wait for the Shortcut round-trip.
    static let defaultTimeout: TimeInterval = 3.0

    /// Continuation used to bridge the URL callback to the async caller.
    private var pendingContinuation: CheckedContinuation<ShortcutsWiFiReading?, Never>?

    // MARK: - Init

    init() {
        // Listen for deep link callback from DeepLinkRouter
        NotificationCenter.default.addObserver(
            forName: .shortcutsWiFiCallbackReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleURLCallback()
            }
        }
    }

    // MARK: - Public API

    /// Triggers the companion Shortcut and waits for Wi-Fi data.
    ///
    /// Returns `nil` if the shortcut is not installed, times out, or fails.
    /// Timeout defaults to 3 seconds (Shortcuts round-trip is typically ~1.5-2.5s).
    func fetchWiFiSignal(timeout: TimeInterval = ShortcutsWiFiProvider.defaultTimeout) async throws -> ShortcutsWiFiReading? {
        // Clear any stale reading from the shared container
        clearSharedReading()

        // Build the Shortcuts URL
        guard let shortcutURL = URL(string: "shortcuts://x-callback-url/run-shortcut?name=Wi-Fi%20to%20NetMonitor&x-success=netmonitor://wifi-result") else {
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

        // Wait for the result with timeout
        let reading = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.pendingContinuation = continuation

                // Set up timeout
                Task<Void, Never> {
                    try? await Task.sleep(for: .seconds(timeout))
                    // If still pending after timeout, resolve with nil
                    self.pendingContinuation?.resume(returning: nil)
                    self.pendingContinuation = nil
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.pendingContinuation?.resume(returning: nil)
                self.pendingContinuation = nil
            }
        }

        if reading != nil {
            isAvailable = true
        }
        return reading
    }

    /// Called when the app receives the `netmonitor://wifi-result` URL callback.
    /// Reads the Wi-Fi data from the shared container and resolves the pending continuation.
    func handleURLCallback() {
        let reading = readSharedReading()
        pendingContinuation?.resume(returning: reading)
        pendingContinuation = nil
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
