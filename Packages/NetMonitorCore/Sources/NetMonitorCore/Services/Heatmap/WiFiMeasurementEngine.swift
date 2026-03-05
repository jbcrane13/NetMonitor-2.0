import Foundation

// MARK: - WiFiMeasurementEngine

public actor WiFiMeasurementEngine: HeatmapServiceProtocol {
    nonisolated(unsafe) private let wifiService: any WiFiInfoServiceProtocol
    nonisolated(unsafe) private let speedTestService: any SpeedTestServiceProtocol
    private let pingService: any PingServiceProtocol

    public var gatewayHost: String = "192.168.1.1"

    private var continuousTask: Task<Void, Never>?
    private var continuousContinuation: AsyncStream<MeasurementPoint>.Continuation?

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

    public func takeMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        let wifi = await fetchWiFiOnMain()
        return buildPoint(from: wifi, x: floorPlanX, y: floorPlanY)
    }

    // MARK: - Active Measurement

    public func takeActiveMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        let wifi = await fetchWiFiOnMain()

        var download: Double?
        var upload: Double?
        do {
            let speedData = try await runSpeedTestOnMain()
            download = speedData.downloadSpeed
            upload = speedData.uploadSpeed
        } catch {
            // Speed test failed; leave speed fields nil
        }

        let pingLatency = await measurePingLatency()

        return buildPoint(
            from: wifi,
            x: floorPlanX,
            y: floorPlanY,
            download: download,
            upload: upload,
            latency: pingLatency
        )
    }

    // MARK: - Continuous Measurement

    public func startContinuousMeasurement(interval: TimeInterval) async -> AsyncStream<MeasurementPoint> {
        await stopContinuousMeasurement()

        let (stream, continuation) = AsyncStream<MeasurementPoint>.makeStream()
        self.continuousContinuation = continuation

        let engine = self
        continuousTask = Task {
            while !Task.isCancelled {
                let point = await engine.takeMeasurement(at: 0, floorPlanY: 0)
                if Task.isCancelled { break }
                continuation.yield(point)
                try? await Task.sleep(for: .seconds(interval))
            }
            continuation.finish()
        }

        return stream
    }

    public func stopContinuousMeasurement() async {
        continuousTask?.cancel()
        continuousTask = nil
        continuousContinuation?.finish()
        continuousContinuation = nil
    }

    // MARK: - MainActor Bridge
    // WiFiInfoServiceProtocol and SpeedTestServiceProtocol methods are @MainActor-isolated.
    // These nonisolated bridge functions access the nonisolated(unsafe) stored properties
    // and await them directly, avoiding actor-boundary sending issues.

    nonisolated private func fetchWiFiOnMain() async -> WiFiInfo? {
        await wifiService.fetchCurrentWiFi()
    }

    nonisolated private func runSpeedTestOnMain() async throws -> SpeedTestData {
        try await speedTestService.startTest()
    }

    // MARK: - Private Helpers

    private func measurePingLatency() async -> Double? {
        let host = gatewayHost
        let stream = await pingService.ping(host: host, count: 3, timeout: 5.0)
        var times: [Double] = []
        for await result in stream where !result.isTimeout {
            times.append(result.time)
        }
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    private func buildPoint(
        from wifi: WiFiInfo?,
        x: Double,
        y: Double,
        download: Double? = nil,
        upload: Double? = nil,
        latency: Double? = nil
    ) -> MeasurementPoint {
        let rssi = wifi?.signalDBm ?? -100
        let noiseFloor = wifi?.noiseLevel
        let snr: Int? = if let noise = noiseFloor { rssi - noise } else { nil }
        let linkSpeed: Int? = wifi?.linkSpeed.map { Int($0) }
        let frequency = parseFrequency(wifi?.frequency)

        return MeasurementPoint(
            floorPlanX: x,
            floorPlanY: y,
            rssi: rssi,
            noiseFloor: noiseFloor,
            snr: snr,
            ssid: wifi?.ssid,
            bssid: wifi?.bssid,
            channel: wifi?.channel,
            frequency: frequency,
            band: wifi?.band,
            linkSpeed: linkSpeed,
            downloadSpeed: download,
            uploadSpeed: upload,
            latency: latency
        )
    }

    private func parseFrequency(_ frequencyString: String?) -> Double? {
        guard let raw = frequencyString else { return nil }
        let cleaned = raw.replacingOccurrences(of: " MHz", with: "")
            .replacingOccurrences(of: "MHz", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 100 else { return nil }
        return value
    }
}
