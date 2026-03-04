import Foundation
import NetMonitorCore

// MARK: - NoOpSpeedTestService

/// A no-op speed test service for passive measurement mode on iOS.
/// Active scan mode requires a real SpeedTestService implementation;
/// for now the heatmap survey only supports passive measurements.
@MainActor
final class NoOpSpeedTestService: SpeedTestServiceProtocol {
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

    func startTest() async throws -> SpeedTestData {
        SpeedTestData(downloadSpeed: 0, uploadSpeed: 0, latency: 0)
    }

    func stopTest() {}
}

// MARK: - NoOpPingService

/// A no-op ping service for passive measurement mode on iOS.
@MainActor
final class NoOpPingService: PingServiceProtocol {
    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        AsyncStream { $0.finish() }
    }

    func stop() async {}

    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? {
        nil
    }
}
