import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@MainActor
private final class MockSamplerWiFiInfoService: WiFiInfoServiceProtocol {
    var currentWiFi: WiFiInfo?
    var isLocationAuthorized: Bool = true
    private var samples: [WiFiInfo?]
    private var sampleIndex = 0

    init(samples: [WiFiInfo?]) {
        self.samples = samples
        self.currentWiFi = samples.first.flatMap { $0 }
    }

    func requestLocationPermission() {}
    func refreshWiFiInfo() {}

    func fetchCurrentWiFi() async -> WiFiInfo? {
        guard !samples.isEmpty else { return nil }
        let sample = samples[min(sampleIndex, samples.count - 1)]
        currentWiFi = sample
        sampleIndex += 1
        return sample
    }
}

@Suite("WiFiSignalSampler")
@MainActor
struct WiFiSignalSamplerTests {
    @Test("uses direct dBm when service provides it")
    func usesDirectDBm() async {
        let service = MockSamplerWiFiInfoService(
            samples: [
                WiFiInfo(ssid: "Office WiFi", bssid: "AA:BB:CC:DD:EE:FF", signalStrength: 78, signalDBm: -47)
            ]
        )
        let sampler = WiFiSignalSampler(wifiService: service)

        let sample = await sampler.currentSample()

        #expect(sample.dbm == -47)
        #expect(sample.ssid == "Office WiFi")
        #expect(sample.bssid == "AA:BB:CC:DD:EE:FF")
    }

    @Test("converts percent strength to approximate dBm when dBm is missing")
    func convertsPercentStrength() async {
        let service = MockSamplerWiFiInfoService(
            samples: [
                WiFiInfo(ssid: "Office WiFi", bssid: nil, signalStrength: 50, signalDBm: nil)
            ]
        )
        let sampler = WiFiSignalSampler(wifiService: service)

        let sample = await sampler.currentSample()

        #expect(sample.dbm == -65)
    }

    @Test("reuses last known dBm across transient nil readings")
    func reusesLastKnownSignalAcrossTransientDrop() async {
        let service = MockSamplerWiFiInfoService(
            samples: [
                WiFiInfo(ssid: "Office WiFi", bssid: "11:22:33:44:55:66", signalStrength: nil, signalDBm: -55),
                nil
            ]
        )
        let sampler = WiFiSignalSampler(wifiService: service)

        let first = await sampler.currentSample()
        let second = await sampler.currentSample()

        #expect(first.dbm == -55)
        #expect(second.dbm == -55)
    }

    @Test("returns default fallback dBm when no WiFi info is available yet")
    func returnsFallbackOnColdStartWithoutWiFiInfo() async {
        let service = MockSamplerWiFiInfoService(samples: [nil])
        let sampler = WiFiSignalSampler(wifiService: service)

        let sample = await sampler.currentSample()

        #expect(sample.dbm == -70)
        #expect(sample.ssid == nil)
        #expect(sample.bssid == nil)
    }
}
