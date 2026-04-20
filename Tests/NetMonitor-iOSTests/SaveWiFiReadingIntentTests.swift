import Foundation
import Testing
@testable import NetMonitor_iOS

// MARK: - SaveWiFiReadingIntent Tests
//
// AppIntents cannot be invoked via `perform()` in unit tests without the full
// Intents runtime. Tests here verify:
//  - The intent's static metadata matches the shared contract exactly.
//  - The intent publishes to WiFiReadingBridge when perform() is called
//    directly (bypassing the Intents runtime).

@MainActor
struct SaveWiFiReadingIntentTests {

    // MARK: - Metadata contract

    @Test("intent title matches shared contract")
    func intentTitle() {
        let title = SaveWiFiReadingIntent.title
        #expect(title.key == "Save Wi-Fi Reading to NetMonitor")
    }

    @Test("openAppWhenRun is true")
    func openAppWhenRunIsTrue() {
        #expect(SaveWiFiReadingIntent.openAppWhenRun == true)
    }

    // MARK: - perform() integration

    @Test("perform publishes reading to WiFiReadingBridge")
    func performPublishesToBridge() async throws {
        var intent = SaveWiFiReadingIntent()
        intent.ssid = "OfficeNet"
        intent.bssid = "11:22:33:44:55:66"
        intent.rssi = -58
        intent.noise = -92
        intent.channel = 44
        intent.txRate = 240.0
        intent.rxRate = 240.0
        intent.wifiStandard = "802.11ax"

        // Start waiting on the bridge before calling perform().
        let bridge = WiFiReadingBridge.shared
        async let waited = bridge.waitForReading(timeout: 2.0)

        // Directly invoke perform() — mirrors what the Intents runtime does.
        _ = try await intent.perform()

        let reading = await waited
        #expect(reading?.ssid == "OfficeNet")
        #expect(reading?.rssi == -58)
        #expect(reading?.channel == 44)
        #expect(reading?.bssid == "11:22:33:44:55:66")
        #expect(reading?.wifiStandard == "802.11ax")
    }

    @Test("perform uses empty string for nil bssid")
    func performUsesFallbackBSSID() async throws {
        var intent = SaveWiFiReadingIntent()
        intent.ssid = "HomeNet"
        intent.bssid = nil
        intent.rssi = -72
        intent.channel = 1

        async let waited = WiFiReadingBridge.shared.waitForReading(timeout: 2.0)
        _ = try await intent.perform()
        let reading = await waited
        #expect(reading?.bssid == "")
    }

    @Test("perform uses zero for nil noise")
    func performUsesFallbackNoise() async throws {
        var intent = SaveWiFiReadingIntent()
        intent.ssid = "GuestNet"
        intent.bssid = "aa:bb:cc:dd:ee:ff"
        intent.rssi = -80
        intent.noise = nil
        intent.channel = 6

        async let waited = WiFiReadingBridge.shared.waitForReading(timeout: 2.0)
        _ = try await intent.perform()
        let reading = await waited
        #expect(reading?.noise == 0)
    }
}
