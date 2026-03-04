import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Mock WiFiInfoService

/// Mock WiFi info service for testing the measurement engine.
/// Returns configurable WiFi data without touching real hardware.
@MainActor
final class MockWiFiInfoService: WiFiInfoServiceProtocol, @unchecked Sendable {
    var currentWiFi: WiFiInfo?
    var isLocationAuthorized: Bool = true
    var fetchCallCount = 0

    /// The WiFiInfo to return from fetchCurrentWiFi().
    var stubbedWiFiInfo: WiFiInfo?

    init(stubbedWiFiInfo: WiFiInfo? = nil) {
        self.stubbedWiFiInfo = stubbedWiFiInfo
        self.currentWiFi = stubbedWiFiInfo
    }

    func requestLocationPermission() {}
    func refreshWiFiInfo() {
        currentWiFi = stubbedWiFiInfo
    }

    func fetchCurrentWiFi() async -> WiFiInfo? {
        fetchCallCount += 1
        return stubbedWiFiInfo
    }
}

// MARK: - Mock SpeedTestService

/// Mock speed test service that returns configurable results.
@MainActor
final class MockSpeedTestService: SpeedTestServiceProtocol, @unchecked Sendable {
    var downloadSpeed: Double = 0
    var uploadSpeed: Double = 0
    var peakDownloadSpeed: Double = 0
    var peakUploadSpeed: Double = 0
    var latency: Double = 0
    var jitter: Double = 0
    var progress: Double = 0
    var phase: SpeedTestPhase = .idle
    var isRunning: Bool = false
    var errorMessage: String?
    var duration: TimeInterval = 6.0
    var selectedServer: SpeedTestServer?
    var startTestCallCount = 0

    /// The SpeedTestData to return from startTest().
    var stubbedResult: SpeedTestData?

    /// If non-nil, startTest() throws this error.
    var stubbedError: Error?

    func startTest() async throws -> SpeedTestData {
        startTestCallCount += 1
        if let error = stubbedError {
            throw error
        }
        return stubbedResult ?? SpeedTestData(
            downloadSpeed: 100.0,
            uploadSpeed: 50.0,
            latency: 15.0
        )
    }

    func stopTest() {
        isRunning = false
    }
}

// MARK: - Mock PingService

/// Mock ping service that returns configurable results.
final class MockPingService: PingServiceProtocol, @unchecked Sendable {
    var pingCallCount = 0
    var lastPingedHost: String?

    /// The PingResults to yield from ping().
    var stubbedResults: [PingResult] = []

    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        pingCallCount += 1
        lastPingedHost = host
        let results = stubbedResults
        return AsyncStream { continuation in
            for result in results {
                continuation.yield(result)
            }
            continuation.finish()
        }
    }

    func stop() async {}

    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? {
        nil
    }
}

// MARK: - Test Helpers

/// Creates a standard WiFiInfo for testing.
private func makeTestWiFiInfo(
    ssid: String = "TestNetwork",
    bssid: String = "AA:BB:CC:DD:EE:FF",
    rssi: Int = -55,
    channel: Int = 6,
    band: WiFiBand = .band2_4GHz,
    noiseLevel: Int? = -90,
    linkSpeed: Double? = nil
) -> WiFiInfo {
    WiFiInfo(
        ssid: ssid,
        bssid: bssid,
        signalStrength: nil,
        signalDBm: rssi,
        channel: channel,
        frequency: nil,
        band: band,
        securityType: "WPA2",
        noiseLevel: noiseLevel,
        linkSpeed: linkSpeed
    )
}

/// Creates a PingResult for testing.
private func makeTestPingResult(
    sequence: Int = 0,
    host: String = "192.168.1.1",
    time: Double = 5.0,
    isTimeout: Bool = false
) -> PingResult {
    PingResult(
        sequence: sequence,
        host: host,
        ipAddress: host,
        ttl: 64,
        time: time,
        size: 64,
        isTimeout: isTimeout,
        method: .icmp
    )
}

// MARK: - WiFiMeasurementEngine Tests

@Suite("WiFiMeasurementEngine")
struct WiFiMeasurementEngineTests {

    // MARK: - Actor Type Verification

    @Test("WiFiMeasurementEngine is an actor conforming to HeatmapServiceProtocol")
    func engineIsActor() async {
        let wifiService = await MockWiFiInfoService()
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        // Verify it conforms to HeatmapServiceProtocol
        let _: any HeatmapServiceProtocol = engine
        // If this compiles, the engine is an actor conforming to the protocol
    }

    // MARK: - Passive Measurement (takeMeasurement)

    @Test("takeMeasurement returns MeasurementPoint with RSSI, SSID, BSSID from WiFi service")
    func passiveMeasurementPopulatesWiFiData() async {
        let wifiInfo = makeTestWiFiInfo(
            ssid: "MyNetwork",
            bssid: "11:22:33:44:55:66",
            rssi: -48,
            channel: 36,
            band: .band5GHz,
            noiseLevel: -85
        )
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: wifiInfo)
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.5, floorPlanY: 0.3)

        #expect(point.rssi == -48)
        #expect(point.ssid == "MyNetwork")
        #expect(point.bssid == "11:22:33:44:55:66")
        #expect(point.channel == 36)
        #expect(point.band == .band5GHz)
        #expect(point.noiseFloor == -85)
        #expect(point.snr == -48 - -85) // 37
        #expect(point.floorPlanX == 0.5)
        #expect(point.floorPlanY == 0.3)
        #expect(point.timestamp <= Date())
    }

    @Test("takeMeasurement delegates to WiFiInfoService")
    func passiveMeasurementDelegatesToWiFiService() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        _ = await engine.takeMeasurement(at: 0.1, floorPlanY: 0.2)

        let callCount = await wifiService.fetchCallCount
        #expect(callCount == 1)
    }

    @Test("takeMeasurement with nil WiFi info returns default RSSI of -100")
    func passiveMeasurementWithNilWiFi() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: nil)
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.0, floorPlanY: 0.0)

        #expect(point.rssi == -100)
        #expect(point.ssid == nil)
        #expect(point.bssid == nil)
        #expect(point.noiseFloor == nil)
        #expect(point.snr == nil)
    }

    @Test("takeMeasurement does NOT populate speed/latency fields")
    func passiveMeasurementOmitsActiveData() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(point.downloadSpeed == nil)
        #expect(point.uploadSpeed == nil)
        #expect(point.latency == nil)

        // Speed test and ping should NOT have been called
        let speedCallCount = await speedTestService.startTestCallCount
        #expect(speedCallCount == 0)
        #expect(pingService.pingCallCount == 0)
    }

    @Test("takeMeasurement preserves floor plan coordinates")
    func passiveMeasurementPreservesCoordinates() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.75, floorPlanY: 0.25)

        #expect(point.floorPlanX == 0.75)
        #expect(point.floorPlanY == 0.25)
    }

    @Test("takeMeasurement computes SNR when noise floor is available")
    func passiveMeasurementComputesSNR() async {
        let wifiInfo = makeTestWiFiInfo(rssi: -45, noiseLevel: -92)
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: wifiInfo)
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(point.snr == 47) // -45 - (-92) = 47
    }

    @Test("takeMeasurement returns nil SNR when noise floor is nil")
    func passiveMeasurementNilSNRWithoutNoiseFloor() async {
        let wifiInfo = makeTestWiFiInfo(rssi: -55, noiseLevel: nil)
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: wifiInfo)
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(point.snr == nil)
    }

    @Test("takeMeasurement maps linkSpeed from WiFiInfo to MeasurementPoint")
    func passiveMeasurementMapsLinkSpeed() async {
        let wifiInfo = makeTestWiFiInfo(rssi: -50, linkSpeed: 866.7)
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: wifiInfo)
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(point.linkSpeed == 866, "Link speed should be mapped from WiFiInfo Double to Int")
    }

    @Test("takeMeasurement returns nil linkSpeed when WiFiInfo.linkSpeed is nil")
    func passiveMeasurementNilLinkSpeed() async {
        let wifiInfo = makeTestWiFiInfo(rssi: -50, linkSpeed: nil)
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: wifiInfo)
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(point.linkSpeed == nil, "Link speed should be nil when WiFiInfo has no link speed")
    }

    // MARK: - Active Measurement (takeActiveMeasurement)

    @Test("takeActiveMeasurement populates downloadSpeed, uploadSpeed, latency")
    func activeMeasurementPopulatesSpeedAndLatency() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        await speedTestService.setStubbedResult(SpeedTestData(
            downloadSpeed: 120.5,
            uploadSpeed: 45.3,
            latency: 12.0
        ))
        let pingService = MockPingService()
        pingService.stubbedResults = [
            makeTestPingResult(sequence: 0, time: 8.0),
            makeTestPingResult(sequence: 1, time: 10.0),
            makeTestPingResult(sequence: 2, time: 12.0),
        ]

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeActiveMeasurement(at: 0.6, floorPlanY: 0.4)

        #expect(point.downloadSpeed == 120.5)
        #expect(point.uploadSpeed == 45.3)
        // Latency is average of ping results: (8 + 10 + 12) / 3 = 10.0
        #expect(point.latency == 10.0)
        // WiFi data should also be present
        #expect(point.rssi == -55)
        #expect(point.ssid == "TestNetwork")
    }

    @Test("takeActiveMeasurement calls speed test and ping services")
    func activeMeasurementDelegatesToServices() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()
        pingService.stubbedResults = [makeTestPingResult()]

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        _ = await engine.takeActiveMeasurement(at: 0.5, floorPlanY: 0.5)

        let speedCallCount = await speedTestService.startTestCallCount
        #expect(speedCallCount == 1)
        #expect(pingService.pingCallCount == 1)
    }

    @Test("takeActiveMeasurement pings the configured gateway host")
    func activeMeasurementPingsGateway() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()
        pingService.stubbedResults = [makeTestPingResult()]

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )
        await engine.setGatewayHost("10.0.0.1")

        _ = await engine.takeActiveMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(pingService.lastPingedHost == "10.0.0.1")
    }

    @Test("takeActiveMeasurement handles speed test failure gracefully")
    func activeMeasurementHandlesSpeedTestFailure() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        await speedTestService.setStubbedError(NSError(domain: "test", code: -1))
        let pingService = MockPingService()
        pingService.stubbedResults = [makeTestPingResult(time: 5.0)]

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeActiveMeasurement(at: 0.5, floorPlanY: 0.5)

        // Speed test failed, so download/upload should be nil
        #expect(point.downloadSpeed == nil)
        #expect(point.uploadSpeed == nil)
        // Ping should still succeed
        #expect(point.latency == 5.0)
        // WiFi data should still be present
        #expect(point.rssi == -55)
    }

    @Test("takeActiveMeasurement handles ping timeout gracefully")
    func activeMeasurementHandlesPingTimeout() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()
        // All pings time out
        pingService.stubbedResults = [
            makeTestPingResult(sequence: 0, time: 0, isTimeout: true),
            makeTestPingResult(sequence: 1, time: 0, isTimeout: true),
        ]

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeActiveMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(point.latency == nil)
        // Speed test should still populate
        #expect(point.downloadSpeed == 100.0) // default mock value
    }

    // MARK: - Continuous Measurement

    @Test("startContinuousMeasurement returns AsyncStream yielding measurements")
    func continuousMeasurementYieldsMeasurements() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo(rssi: -60))
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let stream = await engine.startContinuousMeasurement(interval: 0.05)

        var points: [MeasurementPoint] = []
        for await point in stream {
            points.append(point)
            if points.count >= 3 {
                await engine.stopContinuousMeasurement()
            }
        }

        #expect(points.count >= 3)
        // All points should have WiFi data
        for point in points {
            #expect(point.rssi == -60)
            #expect(point.ssid == "TestNetwork")
        }
    }

    @Test("stopContinuousMeasurement terminates the stream")
    func stopTerminatesStream() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let stream = await engine.startContinuousMeasurement(interval: 0.05)

        // Collect a few measurements
        var count = 0
        for await _ in stream {
            count += 1
            if count >= 2 {
                await engine.stopContinuousMeasurement()
            }
        }

        // Stream should have terminated
        #expect(count >= 2)
    }

    @Test("continuous measurement yields points with default coordinates (0, 0)")
    func continuousMeasurementDefaultCoordinates() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let stream = await engine.startContinuousMeasurement(interval: 0.05)

        for await point in stream {
            #expect(point.floorPlanX == 0)
            #expect(point.floorPlanY == 0)
            await engine.stopContinuousMeasurement()
            break
        }
    }

    @Test("continuous measurement does NOT call speed test or ping")
    func continuousMeasurementIsPassiveOnly() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let stream = await engine.startContinuousMeasurement(interval: 0.05)

        var count = 0
        for await point in stream {
            #expect(point.downloadSpeed == nil)
            #expect(point.uploadSpeed == nil)
            #expect(point.latency == nil)
            count += 1
            if count >= 2 {
                await engine.stopContinuousMeasurement()
            }
        }

        let speedCallCount = await speedTestService.startTestCallCount
        #expect(speedCallCount == 0)
        #expect(pingService.pingCallCount == 0)
    }

    @Test("stopping and restarting continuous measurement works")
    func stopAndRestartContinuousMeasurement() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        // Start first stream and verify it yields values
        let stream1 = await engine.startContinuousMeasurement(interval: 0.05)
        var stream1Count = 0
        for await _ in stream1 {
            stream1Count += 1
            if stream1Count >= 2 {
                await engine.stopContinuousMeasurement()
            }
        }
        #expect(stream1Count >= 2, "First stream should yield at least 2 values")

        // Start second stream after first was stopped
        let stream2 = await engine.startContinuousMeasurement(interval: 0.05)
        var stream2Count = 0
        for await point in stream2 {
            #expect(point.ssid == "TestNetwork", "Second stream should yield valid data")
            stream2Count += 1
            if stream2Count >= 2 {
                await engine.stopContinuousMeasurement()
            }
        }
        #expect(stream2Count >= 2, "Second stream should yield at least 2 values")
    }

    // MARK: - Interval Verification

    @Test("continuous measurement respects the specified interval")
    func continuousMeasurementRespectsInterval() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let interval: TimeInterval = 0.1
        let stream = await engine.startContinuousMeasurement(interval: interval)

        var timestamps: [Date] = []
        for await _ in stream {
            timestamps.append(Date())
            if timestamps.count >= 4 {
                await engine.stopContinuousMeasurement()
            }
        }

        // Verify intervals between consecutive measurements are roughly correct
        guard timestamps.count >= 3 else {
            Issue.record("Expected at least 3 timestamps, got \(timestamps.count)")
            return
        }

        for i in 1 ..< timestamps.count {
            let delta = timestamps[i].timeIntervalSince(timestamps[i - 1])
            // Allow generous tolerance for CI/test environments (50ms to 500ms for 100ms interval)
            #expect(delta >= 0.03, "Interval too short: \(delta)s")
            #expect(delta < 0.5, "Interval too long: \(delta)s")
        }
    }

    // MARK: - Frequency Mapping

    @Test("takeMeasurement maps frequency from WiFiInfo when available as MHz integer")
    func passiveMeasurementMapsFrequencyMHz() async {
        let wifiInfo = WiFiInfo(
            ssid: "TestNet",
            bssid: "AA:BB:CC:DD:EE:FF",
            signalDBm: -50,
            channel: 6,
            frequency: "2437",
            band: .band2_4GHz
        )
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: wifiInfo)
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(point.frequency == 2437, "Frequency should be parsed from WiFiInfo string")
    }

    @Test("takeMeasurement maps frequency with MHz suffix")
    func passiveMeasurementMapsFrequencyWithSuffix() async {
        let wifiInfo = WiFiInfo(
            ssid: "TestNet",
            bssid: "AA:BB:CC:DD:EE:FF",
            signalDBm: -50,
            channel: 36,
            frequency: "5180 MHz",
            band: .band5GHz
        )
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: wifiInfo)
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(point.frequency == 5180, "Frequency with MHz suffix should be parsed")
    }

    @Test("takeMeasurement returns nil frequency for non-parseable string")
    func passiveMeasurementNilFrequencyForGHzString() async {
        let wifiInfo = WiFiInfo(
            ssid: "TestNet",
            bssid: "AA:BB:CC:DD:EE:FF",
            signalDBm: -50,
            channel: 6,
            frequency: "2.4 GHz",
            band: .band2_4GHz
        )
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: wifiInfo)
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(point.frequency == nil, "GHz string is not precise enough for MHz")
    }

    @Test("takeMeasurement returns nil frequency when WiFiInfo.frequency is nil")
    func passiveMeasurementNilFrequencyWhenNil() async {
        let wifiInfo = makeTestWiFiInfo() // frequency is nil by default
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: wifiInfo)
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point = await engine.takeMeasurement(at: 0.5, floorPlanY: 0.5)

        #expect(point.frequency == nil, "Nil WiFiInfo.frequency should remain nil")
    }

    // MARK: - Each MeasurementPoint Has Unique ID and Timestamp

    @Test("each measurement point has unique ID")
    func measurementPointsHaveUniqueIDs() async {
        let wifiService = await MockWiFiInfoService(stubbedWiFiInfo: makeTestWiFiInfo())
        let speedTestService = MockSpeedTestService()
        let pingService = MockPingService()

        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: speedTestService,
            pingService: pingService
        )

        let point1 = await engine.takeMeasurement(at: 0.1, floorPlanY: 0.1)
        let point2 = await engine.takeMeasurement(at: 0.2, floorPlanY: 0.2)

        #expect(point1.id != point2.id)
    }
}

// MARK: - Mock Helper Extensions

extension MockSpeedTestService {
    func setStubbedResult(_ result: SpeedTestData) {
        self.stubbedResult = result
    }

    func setStubbedError(_ error: Error) {
        self.stubbedError = error
    }
}

extension WiFiMeasurementEngine {
    /// Convenience setter for tests.
    func setGatewayHost(_ host: String) {
        self.gatewayHost = host
    }
}
