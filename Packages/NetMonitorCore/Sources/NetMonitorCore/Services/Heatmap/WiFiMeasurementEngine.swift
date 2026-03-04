import Foundation

// MARK: - WiFiMeasurementEngine

/// Actor that orchestrates WiFi measurements for heatmap surveys.
///
/// Provides three measurement modes:
/// - **Passive**: Captures RSSI, SSID, BSSID, channel, band, noise floor via the platform WiFi service.
/// - **Active**: Passive data plus a speed test and gateway ping for download/upload/latency metrics.
/// - **Continuous**: Streams passive measurements at a configurable interval (~500ms default).
///
/// The engine delegates all platform-specific work to injected service protocols,
/// making it fully testable with mock implementations.
public actor WiFiMeasurementEngine: HeatmapServiceProtocol {

    // MARK: - Dependencies

    // WiFiInfoServiceProtocol and SpeedTestServiceProtocol are not Sendable
    // but all their members are @MainActor-isolated, so cross-actor access
    // is safe through await. nonisolated(unsafe) suppresses the false-positive
    // sendability diagnostic while keeping the storage immutable.
    nonisolated(unsafe) private let wifiService: any WiFiInfoServiceProtocol
    nonisolated(unsafe) private let speedTestService: any SpeedTestServiceProtocol
    private let pingService: any PingServiceProtocol

    // MARK: - Configuration

    /// The gateway host to ping during active measurements.
    /// Set this before calling `takeActiveMeasurement()`.
    public var gatewayHost: String = "192.168.1.1"

    // MARK: - Continuous Measurement State

    /// The task driving the continuous measurement loop.
    private var continuousTask: Task<Void, Never>?

    /// The continuation for the current continuous measurement stream.
    private var continuousContinuation: AsyncStream<MeasurementPoint>.Continuation?

    // MARK: - Init

    /// Creates a new measurement engine with the given platform services.
    ///
    /// - Parameters:
    ///   - wifiService: Provides current WiFi information (RSSI, SSID, etc.).
    ///   - speedTestService: Runs download/upload speed tests.
    ///   - pingService: Performs ICMP/TCP ping to measure latency.
    public init(
        wifiService: any WiFiInfoServiceProtocol,
        speedTestService: any SpeedTestServiceProtocol,
        pingService: any PingServiceProtocol
    ) {
        self.wifiService = wifiService
        self.speedTestService = speedTestService
        self.pingService = pingService
    }

    // MARK: - Passive Measurement

    /// Takes a single passive WiFi measurement at the given floor plan coordinates.
    ///
    /// Captures: RSSI, SSID, BSSID, channel, band, noise floor (macOS only), link speed.
    /// Returns immediately after reading from the platform WiFi service.
    ///
    /// - Parameters:
    ///   - floorPlanX: Normalized X position on the floor plan (0.0–1.0).
    ///   - floorPlanY: Normalized Y position on the floor plan (0.0–1.0).
    /// - Returns: A `MeasurementPoint` populated with passive WiFi data.
    public func takeMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        let wifiInfo = await wifiService.fetchCurrentWiFi()
        return buildMeasurementPoint(
            floorPlanX: floorPlanX,
            floorPlanY: floorPlanY,
            wifiInfo: wifiInfo
        )
    }

    // MARK: - Active Measurement

    /// Takes an active measurement: passive WiFi data plus a speed test and gateway ping.
    ///
    /// The speed test runs for ~6 seconds (per the service's `duration` setting).
    /// A gateway ping runs concurrently to measure local network latency.
    ///
    /// - Parameters:
    ///   - floorPlanX: Normalized X position on the floor plan (0.0–1.0).
    ///   - floorPlanY: Normalized Y position on the floor plan (0.0–1.0).
    /// - Returns: A `MeasurementPoint` with passive WiFi data, speed test results, and ping latency.
    public func takeActiveMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        // Capture passive WiFi data first
        let wifiInfo = await wifiService.fetchCurrentWiFi()

        // Run speed test and gateway ping concurrently
        let host = gatewayHost
        async let speedTestResult = runSpeedTest()
        async let pingLatency = measureGatewayLatency(host: host)

        let speedData = await speedTestResult
        let latency = await pingLatency

        return buildMeasurementPoint(
            floorPlanX: floorPlanX,
            floorPlanY: floorPlanY,
            wifiInfo: wifiInfo,
            downloadSpeed: speedData?.downloadSpeed,
            uploadSpeed: speedData?.uploadSpeed,
            latency: latency
        )
    }

    // MARK: - Continuous Measurement

    /// Starts continuous passive measurements at the specified interval.
    ///
    /// Each tick captures passive WiFi data and yields a `MeasurementPoint`
    /// with `floorPlanX = 0` and `floorPlanY = 0` (the caller is responsible
    /// for enriching the position, e.g., from AR tracking).
    ///
    /// Call `stopContinuousMeasurement()` to terminate the stream.
    /// Starting a new continuous measurement automatically stops any previous one.
    ///
    /// - Parameter interval: Time between measurements in seconds (default 0.5).
    /// - Returns: An `AsyncStream` that yields `MeasurementPoint` values.
    public func startContinuousMeasurement(interval: TimeInterval = 0.5) async -> AsyncStream<MeasurementPoint> {
        // Stop any existing continuous measurement
        stopContinuousInternal()

        let (stream, continuation) = AsyncStream.makeStream(of: MeasurementPoint.self)
        self.continuousContinuation = continuation

        let intervalNanoseconds = UInt64(interval * 1_000_000_000)

        // Capture the continuation locally so the task only finishes its OWN
        // continuation, not a replacement set by a subsequent start call.
        let taskContinuation = continuation

        continuousTask = Task { [weak self] in
            guard let self else {
                taskContinuation.finish()
                return
            }
            while !Task.isCancelled {
                let wifiInfo = await self.wifiService.fetchCurrentWiFi()
                let point = self.buildMeasurementPoint(
                    floorPlanX: 0,
                    floorPlanY: 0,
                    wifiInfo: wifiInfo
                )
                taskContinuation.yield(point)

                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    break
                }
            }
            taskContinuation.finish()
        }

        return stream
    }

    /// Stops the current continuous measurement stream, if any.
    public func stopContinuousMeasurement() async {
        stopContinuousInternal()
    }

    /// Synchronous stop used internally to avoid async reentrancy issues.
    private func stopContinuousInternal() {
        continuousTask?.cancel()
        continuousTask = nil
        continuousContinuation?.finish()
        continuousContinuation = nil
    }

    // MARK: - Private Helpers

    /// Runs the speed test via the injected service.
    private func runSpeedTest() async -> SpeedTestData? {
        do {
            return try await speedTestService.startTest()
        } catch {
            return nil
        }
    }

    /// Pings the gateway host and returns the average latency in milliseconds.
    private func measureGatewayLatency(host: String) async -> Double? {
        var latencies: [Double] = []
        let stream = await pingService.ping(host: host, count: 3, timeout: 2.0)

        for await result in stream where !result.isTimeout {
            latencies.append(result.time)
        }

        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    /// Builds a `MeasurementPoint` from WiFi info and optional active measurement data.
    nonisolated private func buildMeasurementPoint(
        floorPlanX: Double,
        floorPlanY: Double,
        wifiInfo: WiFiInfo?,
        downloadSpeed: Double? = nil,
        uploadSpeed: Double? = nil,
        latency: Double? = nil
    ) -> MeasurementPoint {
        let rssi = wifiInfo?.signalDBm ?? wifiInfo?.signalStrength ?? -100
        let noiseFloor = wifiInfo?.noiseLevel
        let snr: Int? = if let noise = noiseFloor { rssi - noise } else { nil }

        // Map frequency from WiFiInfo (String?, e.g. "2437" or "5 GHz") to Int? (MHz).
        let frequency: Int? = wifiInfo?.frequency.flatMap { Self.parseFrequencyMHz($0) }

        // Map link speed from Double? (Mbps) to Int? for the measurement point.
        let linkSpeed: Int? = wifiInfo?.linkSpeed.map { Int($0) }

        return MeasurementPoint(
            floorPlanX: floorPlanX,
            floorPlanY: floorPlanY,
            rssi: rssi,
            noiseFloor: noiseFloor,
            snr: snr,
            ssid: wifiInfo?.ssid,
            bssid: wifiInfo?.bssid,
            channel: wifiInfo?.channel,
            frequency: frequency,
            band: wifiInfo?.band,
            linkSpeed: linkSpeed,
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            latency: latency,
            connectedAPName: nil
        )
    }

    /// Parses a frequency string from WiFiInfoServiceProtocol into MHz as Int.
    ///
    /// Handles formats like:
    /// - `"2437"` → 2437 (already MHz)
    /// - `"5180 MHz"` → 5180
    /// - `"2.4 GHz"` → nil (not precise enough for MHz)
    nonisolated private static func parseFrequencyMHz(_ string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        // Try direct integer parse (e.g. "2437")
        if let value = Int(trimmed) {
            return value
        }

        // Try stripping "MHz" suffix (e.g. "5180 MHz")
        let lowered = trimmed.lowercased()
        if lowered.hasSuffix("mhz") {
            let numeric = lowered.replacingOccurrences(of: "mhz", with: "")
                .trimmingCharacters(in: .whitespaces)
            return Int(numeric)
        }

        return nil
    }
}
