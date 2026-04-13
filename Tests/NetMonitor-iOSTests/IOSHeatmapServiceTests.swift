import Testing
import Foundation
import CoreLocation
import NetMonitorCore
@testable import NetMonitor_iOS

// MARK: - Mock WiFiInfoService

private final class MockHeatmapWiFiInfoService: WiFiInfoServiceProtocol, @unchecked Sendable {
    var currentWiFi: WiFiInfo?
    var isLocationAuthorized: Bool = true
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var stubbedFetchResult: WiFiInfo?

    func requestLocationPermission() {}
    func refreshWiFiInfo() {}

    func fetchCurrentWiFi() async -> WiFiInfo? {
        return stubbedFetchResult
    }
}

// MARK: - Mock SpeedTestService

private final class MockHeatmapSpeedTestService: SpeedTestServiceProtocol, @unchecked Sendable {
    var downloadSpeed: Double = 0
    var uploadSpeed: Double = 0
    var peakDownloadSpeed: Double = 0
    var peakUploadSpeed: Double = 0
    var latency: Double = 0
    var jitter: Double = 0
    var isRunning: Bool = false
    var phase: SpeedTestPhase = .idle
    var progress: Double = 0
    var errorMessage: String?
    var duration: TimeInterval = 10
    var selectedServer: SpeedTestServer?

    var stubbedResult: SpeedTestData?
    var shouldThrow = false

    func startTest() async throws -> SpeedTestData {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return stubbedResult ?? SpeedTestData(downloadSpeed: 100, uploadSpeed: 50, latency: 15)
    }

    func stopTest() {}
}

// MARK: - Mock PingService for Heatmap

private final class MockHeatmapPingService: PingServiceProtocol, @unchecked Sendable {
    var mockResults: [PingResult] = []

    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        let results = mockResults
        return AsyncStream { continuation in
            for result in results { continuation.yield(result) }
            continuation.finish()
        }
    }

    func stop() async {}

    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? {
        return nil
    }
}

// MARK: - IOSHeatmapServiceTests

@MainActor
struct IOSHeatmapServiceMeasurementTests {

    private func makeSUT(
        wifiInfo: WiFiInfo? = nil,
        speedResult: SpeedTestData? = nil,
        speedThrows: Bool = false,
        pingResults: [PingResult] = []
    ) -> (IOSHeatmapService, MockHeatmapWiFiInfoService, MockHeatmapSpeedTestService, MockHeatmapPingService) {
        let wifi = MockHeatmapWiFiInfoService()
        wifi.stubbedFetchResult = wifiInfo
        let speed = MockHeatmapSpeedTestService()
        speed.stubbedResult = speedResult
        speed.shouldThrow = speedThrows
        let ping = MockHeatmapPingService()
        ping.mockResults = pingResults
        let service = IOSHeatmapService(
            wifiInfoService: wifi,
            speedTestService: speed,
            pingService: ping
        )
        return (service, wifi, speed, ping)
    }

    private func sampleWiFiInfo() -> WiFiInfo {
        WiFiInfo(
            ssid: "TestNet",
            bssid: "AA:BB:CC:DD:EE:FF",
            signalStrength: 80,
            signalDBm: -55,
            channel: 36,
            frequency: "5180 MHz",
            band: .band5GHz,
            securityType: "WPA3",
            noiseLevel: -90,
            linkSpeed: 866
        )
    }

    // MARK: - takeMeasurement (passive scan)

    @Test("Passive measurement returns point with RSSI from WiFi data")
    func passiveMeasurementReturnsRSSI() async {
        let wifi = sampleWiFiInfo()
        let (service, _, _, _) = makeSUT(wifiInfo: wifi)
        let point = await service.takeMeasurement(at: 0.5, floorPlanY: 0.7)
        #expect(point.rssi == -55)
        #expect(point.floorPlanX == 0.5)
        #expect(point.floorPlanY == 0.7)
    }

    @Test("Passive measurement populates SSID and BSSID")
    func passiveMeasurementPopulatesSSID() async {
        let (service, _, _, _) = makeSUT(wifiInfo: sampleWiFiInfo())
        let point = await service.takeMeasurement(at: 0, floorPlanY: 0)
        #expect(point.ssid == "TestNet")
        #expect(point.bssid == "AA:BB:CC:DD:EE:FF")
    }

    @Test("Passive measurement populates channel and band")
    func passiveMeasurementPopulatesChannelAndBand() async {
        let (service, _, _, _) = makeSUT(wifiInfo: sampleWiFiInfo())
        let point = await service.takeMeasurement(at: 0, floorPlanY: 0)
        #expect(point.channel == 36)
        #expect(point.band == .band5GHz)
    }

    @Test("Passive measurement computes SNR from RSSI and noise floor")
    func passiveMeasurementComputesSNR() async {
        let (service, _, _, _) = makeSUT(wifiInfo: sampleWiFiInfo())
        let point = await service.takeMeasurement(at: 0, floorPlanY: 0)
        // SNR = rssi - noiseFloor = -55 - (-90) = 35
        #expect(point.snr == 35)
    }

    @Test("Passive measurement has nil speed and latency fields")
    func passiveMeasurementHasNilSpeedFields() async {
        let (service, _, _, _) = makeSUT(wifiInfo: sampleWiFiInfo())
        let point = await service.takeMeasurement(at: 0, floorPlanY: 0)
        #expect(point.downloadSpeed == nil)
        #expect(point.uploadSpeed == nil)
        #expect(point.latency == nil)
    }

    @Test("Passive measurement defaults RSSI to -100 when WiFi data is nil")
    func passiveMeasurementDefaultsRSSIWhenNil() async {
        let (service, _, _, _) = makeSUT(wifiInfo: nil)
        let point = await service.takeMeasurement(at: 0, floorPlanY: 0)
        #expect(point.rssi == -100)
        #expect(point.ssid == nil)
    }

    // MARK: - takeActiveMeasurement

    @Test("Active measurement includes speed test results")
    func activeMeasurementIncludesSpeedTest() async {
        let speedData = SpeedTestData(downloadSpeed: 200, uploadSpeed: 80, latency: 10)
        let pingResults = [
            PingResult(sequence: 1, host: "192.168.1.1", ttl: 64, time: 5.0),
            PingResult(sequence: 2, host: "192.168.1.1", ttl: 64, time: 7.0),
            PingResult(sequence: 3, host: "192.168.1.1", ttl: 64, time: 6.0),
        ]
        let (service, _, _, _) = makeSUT(
            wifiInfo: sampleWiFiInfo(),
            speedResult: speedData,
            pingResults: pingResults
        )
        let point = await service.takeActiveMeasurement(at: 0.3, floorPlanY: 0.4)
        #expect(point.downloadSpeed == 200)
        #expect(point.uploadSpeed == 80)
        // Average latency: (5 + 7 + 6) / 3 = 6.0
        #expect(point.latency == 6.0)
        #expect(point.rssi == -55)
    }

    @Test("Active measurement leaves speed nil when speed test throws")
    func activeMeasurementHandlesSpeedTestFailure() async {
        let (service, _, _, _) = makeSUT(
            wifiInfo: sampleWiFiInfo(),
            speedThrows: true,
            pingResults: [PingResult(sequence: 1, host: "gw", ttl: 64, time: 3.0)]
        )
        let point = await service.takeActiveMeasurement(at: 0, floorPlanY: 0)
        #expect(point.downloadSpeed == nil)
        #expect(point.uploadSpeed == nil)
        // Ping still works even when speed test fails
        #expect(point.latency == 3.0)
    }

    @Test("Active measurement returns nil latency when all pings timeout")
    func activeMeasurementNilLatencyOnTimeout() async {
        let timeoutPing = PingResult(sequence: 1, host: "gw", ttl: 0, time: 0, isTimeout: true)
        let (service, _, _, _) = makeSUT(
            wifiInfo: sampleWiFiInfo(),
            pingResults: [timeoutPing]
        )
        let point = await service.takeActiveMeasurement(at: 0, floorPlanY: 0)
        #expect(point.latency == nil)
    }

    // MARK: - Frequency parsing

    @Test("Passive measurement parses frequency string to Double")
    func frequencyParsing() async {
        let (service, _, _, _) = makeSUT(wifiInfo: sampleWiFiInfo())
        let point = await service.takeMeasurement(at: 0, floorPlanY: 0)
        #expect(point.frequency == 5180)
    }

    // MARK: - Link speed

    @Test("Passive measurement converts linkSpeed Double to Int")
    func linkSpeedConversion() async {
        let (service, _, _, _) = makeSUT(wifiInfo: sampleWiFiInfo())
        let point = await service.takeMeasurement(at: 0, floorPlanY: 0)
        #expect(point.linkSpeed == 866)
    }
}
