import Foundation
import Testing
@testable import NetMonitor_iOS

// MARK: - WiFiReadingBridge Tests

@MainActor
struct WiFiReadingBridgeTests {

    // MARK: - Helpers

    private func makeReading(rssi: Int = -65, channel: Int = 6) -> ShortcutsWiFiReading {
        ShortcutsWiFiReading(
            ssid: "TestNet",
            bssid: "aa:bb:cc:dd:ee:ff",
            rssi: rssi,
            noise: -90,
            channel: channel,
            txRate: 144.0,
            rxRate: 144.0,
            wifiStandard: "802.11ax",
            timestamp: Date()
        )
    }

    // MARK: - publish before wait

    @Test("publish before waitForReading resolves via fallback file — bridge returns nil for missed in-process delivery")
    func publishBeforeWaitReturnsMissedReading() async {
        // Simulate the cold-launch edge case: publish fires before wait is registered.
        // The bridge itself will return nil (no listener); the provider falls back to file.
        let bridge = WiFiReadingBridge()
        let reading = makeReading()
        bridge.publish(reading) // no continuations registered — no-op

        // A subsequent wait must timeout (no pending publish will arrive).
        let result = await bridge.waitForReading(timeout: 0.05)
        #expect(result == nil)
    }

    // MARK: - publish during wait

    @Test("publish during waitForReading resolves continuation with reading")
    func publishDuringWaitResolvesReading() async {
        let bridge = WiFiReadingBridge()
        let reading = makeReading(rssi: -55, channel: 36)

        // Start waiting, then publish after a small delay.
        async let waited = bridge.waitForReading(timeout: 2.0)

        Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(50))
            bridge.publish(reading)
        }

        let result = await waited
        #expect(result?.rssi == -55)
        #expect(result?.channel == 36)
        #expect(result?.ssid == "TestNet")
    }

    // MARK: - timeout

    @Test("waitForReading returns nil after timeout when no publish arrives")
    func waitForReadingTimesOut() async {
        let bridge = WiFiReadingBridge()
        let result = await bridge.waitForReading(timeout: 0.05)
        #expect(result == nil)
    }

    // MARK: - multiple waiters

    @Test("publish resolves all pending continuations")
    func publishResolvesMultipleWaiters() async {
        let bridge = WiFiReadingBridge()
        let reading = makeReading(rssi: -70)

        async let r1 = bridge.waitForReading(timeout: 2.0)
        async let r2 = bridge.waitForReading(timeout: 2.0)

        Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(50))
            bridge.publish(reading)
        }

        let (result1, result2) = await (r1, r2)
        #expect(result1?.rssi == -70)
        #expect(result2?.rssi == -70)
    }

    // MARK: - no double-resume

    @Test("publish after timeout does not double-resume (no crash)")
    func publishAfterTimeoutDoesNotCrash() async {
        let bridge = WiFiReadingBridge()
        let reading = makeReading()

        // Wait with a very short timeout so it expires first.
        let result = await bridge.waitForReading(timeout: 0.05)
        #expect(result == nil)

        // Publish after expiry — should be a safe no-op.
        bridge.publish(reading)
        // If this crashes, the test fails automatically.
    }

    // MARK: - writeBackup

    @Test("writeBackup writes decodable JSON to App Group container")
    func writeBackupWritesDecodableJSON() {
        let reading = makeReading(rssi: -60, channel: 11)
        WiFiReadingBridge.writeBackup(reading)

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WiFiReadingBridge.appGroupID
        ) else {
            // App Group not available in test sandbox — skip gracefully.
            return
        }
        let fileURL = containerURL.appendingPathComponent(WiFiReadingBridge.readingFilename)
        guard let data = try? Data(contentsOf: fileURL) else {
            Issue.record("Backup file not found at \(fileURL.path)")
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode(ShortcutsWiFiReading.self, from: data)
        #expect(decoded?.rssi == -60)
        #expect(decoded?.channel == 11)
    }
}
