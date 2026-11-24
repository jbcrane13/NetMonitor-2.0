import Testing
import Foundation
@testable import NetMonitorCore

/// A measurement with no Wi-Fi signal reading is flagged at capture, so the heatmap advisor can
/// leave it out (#455).
@Suite("WiFiMeasurementEngine readings")
struct WiFiMeasurementReadingTests {
    @Test func aMeasurementWithNoReadingIsFlaggedAndARealOneIsNot() async {
        let none = await WiFiMeasurementEngine(
            wifiService: MockWiFiInfoService(),
            speedTestService: MockSpeedTestService(),
            pingService: MockPingService()
        )
        let wifi = WiFiInfo(
            ssid: "TestNetwork", bssid: "AA:BB:CC:DD:EE:FF", signalStrength: nil, signalDBm: -61, channel: 6,
            frequency: nil, band: .band2_4GHz, securityType: "WPA2", noiseLevel: -90, linkSpeed: nil
        )
        let measured = await WiFiMeasurementEngine(
            wifiService: MockWiFiInfoService(stubbedWiFiInfo: wifi),
            speedTestService: MockSpeedTestService(),
            pingService: MockPingService()
        )

        let missing = await none.takeMeasurement(at: 0.5, floorPlanY: 0.5)
        let reading = await measured.takeMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(missing.rssi == -100)
        #expect(missing.rssiUnavailable == true)
        #expect(reading.rssi == -61)
        #expect(reading.rssiUnavailable == nil)
    }

    @Test func aPointSavedBeforeTheFlagDecodesAsMeasured() throws {
        let json = #"{"id":"\#(UUID())","timestamp":0,"floorPlanX":0.5,"floorPlanY":0.5,"rssi":-61}"#

        let point = try JSONDecoder().decode(MeasurementPoint.self, from: Data(json.utf8))

        #expect(point.rssiUnavailable == nil)
    }
}
