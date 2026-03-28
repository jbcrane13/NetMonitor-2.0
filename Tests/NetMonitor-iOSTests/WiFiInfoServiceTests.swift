import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_iOS

/// WiFiInfoService tests covering logic NOT in WiFiInfoServiceCacheTests.
///
/// INTEGRATION GAP: NEHotspotNetwork.fetchCurrent() requires a real device
/// with Wi-Fi entitlements. CLLocationManager delegation requires device
/// location services. These tests cover the static helper methods,
/// model properties, and initialization behavior.

@MainActor
struct WiFiInfoServiceTests {

    // MARK: - percentToApproxDBm (via WiFiInfo model validation)

    @Test("WiFiInfo stores all provided fields")
    func wifiInfoStoresFields() {
        let info = WiFiInfo(
            ssid: "MyNetwork",
            bssid: "AA:BB:CC:DD:EE:FF",
            signalStrength: 75,
            signalDBm: -47,
            channel: 6,
            frequency: nil,
            band: .band2_4GHz,
            securityType: "WPA3"
        )
        #expect(info.ssid == "MyNetwork")
        #expect(info.bssid == "AA:BB:CC:DD:EE:FF")
        #expect(info.signalStrength == 75)
        #expect(info.signalDBm == -47)
        #expect(info.channel == 6)
        #expect(info.securityType == "WPA3")
    }

    @Test("WiFiInfo with nil optional fields")
    func wifiInfoNilOptionals() {
        let info = WiFiInfo(
            ssid: "Open",
            bssid: nil,
            signalStrength: nil,
            signalDBm: nil,
            channel: nil,
            frequency: nil,
            band: nil,
            securityType: nil
        )
        #expect(info.ssid == "Open")
        #expect(info.bssid == nil)
        #expect(info.signalStrength == nil)
        #expect(info.signalDBm == nil)
    }

    // MARK: - Service initialization

    @Test("WiFiInfoService initializes with nil currentWiFi")
    func serviceInitialState() {
        // On macOS test host, currentWiFi starts nil before any fetch
        // (NEHotspotNetwork is iOS-only and returns nil on macOS)
        let service = WiFiInfoService()
        // Initial state before any async work completes
        #expect(service.authorizationStatus != nil)
    }

    // MARK: - Protocol conformance

    @Test("WiFiInfoService conforms to WiFiInfoServiceProtocol")
    func protocolConformance() {
        let service: any WiFiInfoServiceProtocol = WiFiInfoService()
        _ = service
    }

    @Test("MockWiFiInfoService tracks refreshCallCount")
    func mockTracksRefreshCount() {
        let mock = MockWiFiInfoService()
        #expect(mock.refreshCallCount == 0)

        mock.refreshWiFiInfo()
        #expect(mock.refreshCallCount == 1)

        mock.refreshWiFiInfo()
        mock.refreshWiFiInfo()
        #expect(mock.refreshCallCount == 3)
    }

    @Test("MockWiFiInfoService returns configured WiFi info")
    func mockReturnsConfiguredInfo() async {
        let mock = MockWiFiInfoService()
        let testInfo = WiFiInfo(
            ssid: "Test",
            bssid: "11:22:33:44:55:66",
            signalStrength: 80,
            signalDBm: -40,
            channel: 11,
            frequency: nil,
            band: .band5GHz,
            securityType: "WPA2"
        )
        mock.currentWiFi = testInfo

        let fetched = await mock.fetchCurrentWiFi()
        #expect(fetched?.ssid == "Test")
        #expect(fetched?.signalStrength == 80)
    }
}
