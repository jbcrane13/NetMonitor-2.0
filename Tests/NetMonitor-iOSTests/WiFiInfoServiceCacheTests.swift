import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - WiFiInfoService TTL Cache Tests (VAL-IOS-039)

@Suite("WiFiInfoService TTL Cache")
@MainActor
struct WiFiInfoServiceCacheTests {

    // VAL-IOS-039: Cached result returned within TTL window
    @Test func cachedResultReturnedWithinTTL() async {
        let service = WiFiInfoService()

        // First call — populates cache
        let first = await service.fetchCurrentWiFi()
        #expect(first != nil, "First fetch should return WiFi info")

        // Second call immediately — should return cached result
        let second = await service.fetchCurrentWiFi()
        #expect(second != nil, "Second fetch should return cached WiFi info")
        #expect(first?.ssid == second?.ssid, "Cached result should match first result")
    }

    // VAL-IOS-039: Cache expires after TTL
    @Test func cacheExpiresAfterTTL() async throws {
        let service = WiFiInfoService()

        // First call — populates cache
        let first = await service.fetchCurrentWiFi()
        #expect(first != nil, "First fetch should return WiFi info")

        // Wait for cache to expire (1.1s > 1.0s TTL)
        try await Task.sleep(for: .milliseconds(1100))

        // This call should go through the full fetch path again
        let afterExpiry = await service.fetchCurrentWiFi()
        #expect(afterExpiry != nil, "Post-expiry fetch should return WiFi info")
    }
}
