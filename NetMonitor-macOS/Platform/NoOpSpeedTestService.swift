import Foundation
import NetMonitorCore

// MARK: - NoOpSpeedTestService

/// A no-op speed test service used for passive measurement mode.
/// Active scan mode will be implemented in a later feature.
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
