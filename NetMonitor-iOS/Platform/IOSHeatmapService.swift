import Foundation
import NetMonitorCore

// MARK: - IOSHeatmapService

/// iOS implementation of ``HeatmapServiceProtocol``.
///
/// Uses ``ShortcutsWiFiProvider`` as the primary signal source (reliable RSSI via
/// Apple Shortcuts automation), falling back to ``WiFiInfoService`` which wraps
/// `NEHotspotNetwork.fetchCurrent()`. Active measurements layer speed-test and
/// ping results on top of the passive Wi-Fi data.
///
/// See `docs/iOS-WiFi-Heatmap-Spec.md` sections 2, 4, 7 for design rationale.
@MainActor
@Observable
final class IOSHeatmapService: HeatmapServiceProtocol, @unchecked Sendable {

    // MARK: - Dependencies

    private let wifiInfoService: any WiFiInfoServiceProtocol
    private let shortcutsProvider: ShortcutsWiFiProvider
    nonisolated(unsafe) private let speedTestService: any SpeedTestServiceProtocol
    private let pingService: any PingServiceProtocol

    /// Gateway host for latency probes during active measurements.
    var gatewayHost: String = "192.168.1.1"

    // MARK: - Continuous Measurement State

    private var continuousTask: Task<Void, Never>?
    private var continuousContinuation: AsyncStream<MeasurementPoint>.Continuation?

    // MARK: - Init

    init(
        wifiInfoService: any WiFiInfoServiceProtocol,
        shortcutsProvider: ShortcutsWiFiProvider = ShortcutsWiFiProvider(),
        speedTestService: any SpeedTestServiceProtocol,
        pingService: any PingServiceProtocol
    ) {
        self.wifiInfoService = wifiInfoService
        self.shortcutsProvider = shortcutsProvider
        self.speedTestService = speedTestService
        self.pingService = pingService
    }

    // MARK: - HeatmapServiceProtocol

    func takeMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        let wifi = await fetchWiFiData()
        return buildPoint(from: wifi, x: floorPlanX, y: floorPlanY)
    }

    func takeActiveMeasurement(at floorPlanX: Double, floorPlanY: Double) async -> MeasurementPoint {
        let wifi = await fetchWiFiData()

        var download: Double?
        var upload: Double?
        do {
            let speedData = try await runSpeedTest()
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

    func startContinuousMeasurement(interval: TimeInterval) async -> AsyncStream<MeasurementPoint> {
        await stopContinuousMeasurement()

        let (stream, continuation) = AsyncStream<MeasurementPoint>.makeStream()
        self.continuousContinuation = continuation

        continuousTask = Task<Void, Never> {
            while !Task.isCancelled {
                let point = await self.takeMeasurement(at: 0, floorPlanY: 0)
                if Task.isCancelled { break }
                continuation.yield(point)
                try? await Task.sleep(for: .seconds(interval))
            }
            continuation.finish()
        }

        return stream
    }

    func stopContinuousMeasurement() async {
        continuousTask?.cancel()
        continuousTask = nil
        continuousContinuation?.finish()
        continuousContinuation = nil
    }

    // MARK: - WiFi Data Acquisition

    /// Fetches Wi-Fi data using the Shortcuts provider as primary source,
    /// falling back to NEHotspotNetwork via WiFiInfoService.
    private func fetchWiFiData() async -> WiFiInfo? {
        // Primary: Shortcuts-based measurement (reliable RSSI)
        if let reading = try? await shortcutsProvider.fetchWiFiSignal() {
            return ShortcutsWiFiProvider.wifiInfo(from: reading)
        }

        // Fallback: NEHotspotNetwork via WiFiInfoService
        return await wifiInfoService.fetchCurrentWiFi()
    }

    // MARK: - Speed Test Bridge

    nonisolated private func runSpeedTest() async throws -> SpeedTestData {
        try await speedTestService.startTest()
    }

    // MARK: - Ping Latency

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

    // MARK: - Point Builder

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
