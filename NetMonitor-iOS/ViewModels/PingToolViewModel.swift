import Foundation
import NetMonitorCore

/// ViewModel for the Ping tool view
@MainActor
@Observable
final class PingToolViewModel {
    // MARK: - Input Properties

    var host: String = ""
    var pingCount: Int = UserDefaults.standard.object(forKey: AppSettings.Keys.defaultPingCount) as? Int ?? 20 {
        didSet { UserDefaults.standard.set(pingCount, forKey: AppSettings.Keys.defaultPingCount) }
    }

    // MARK: - State Properties

    var isRunning: Bool = false
    var results: [PingResult] = []
    var statistics: PingStatistics?
    var errorMessage: String?

    // MARK: - Configuration

    let availablePingCounts = [4, 10, 20, 50, 100]

    // MARK: - Dependencies

    private let pingService: any PingServiceProtocol
    private var pingTask: Task<Void, Never>?

    init(pingService: any PingServiceProtocol = PingService(), initialHost: String? = nil) {
        self.pingService = pingService
        if let initialHost = initialHost {
            self.host = initialHost
        }
    }

    // MARK: - Computed Properties

    var canStartPing: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && !isRunning
    }

    // MARK: - Actions

    func startPing() {
        guard canStartPing else { return }

        clearResults()
        isRunning = true

        pingTask = Task {
            let timeout = UserDefaults.standard.object(forKey: AppSettings.Keys.pingTimeout) as? Double ?? 5.0
            let stream = await pingService.ping(
                host: host.trimmingCharacters(in: .whitespaces),
                count: pingCount,
                timeout: timeout
            )

            for await result in stream {
                guard !Task.isCancelled else { break }
                results.append(result)
            }

            guard !Task.isCancelled else { return }

            // Calculate statistics after completion
            statistics = await pingService.calculateStatistics(results, requestedCount: pingCount)
            isRunning = false

            if let stats = statistics {
                ToolActivityLog.shared.add(
                    tool: "Ping",
                    target: host,
                    result: stats.received > 0 ? "\(String(format: "%.0f", stats.avgTime)) ms avg" : "No response",
                    success: stats.received > 0
                )
            }
        }
    }

    func stopPing() {
        pingTask?.cancel()
        pingTask = nil
        Task {
            await pingService.stop()
        }
        isRunning = false
    }

    func clearResults() {
        results.removeAll()
        statistics = nil
        errorMessage = nil
    }

    // MARK: - Chart Data

    var successfulPings: [PingResult] {
        results.filter { !$0.isTimeout }
    }

    var liveAvgLatency: Double {
        let times = successfulPings.map(\.time)
        guard !times.isEmpty else { return 0 }
        return times.reduce(0, +) / Double(times.count)
    }

    var liveMinLatency: Double {
        successfulPings.map(\.time).min() ?? 0
    }

    var liveMaxLatency: Double {
        successfulPings.map(\.time).max() ?? 0
    }

    /// Y-axis min floored below the P5 value so variance is visually prominent.
    /// Always at least 0 (never negative latency).
    var chartYAxisMin: Double {
        let times = successfulPings.map(\.time).sorted()
        guard times.count >= 2 else { return 0 }
        let p5Index = Int(Double(times.count - 1) * 0.05)
        let p5 = times[p5Index]
        // Floor to ~80% of P5, rounded down to nearest 5ms, but never below 0
        let floor = max((p5 * 0.8), 0)
        return (floor / 5).rounded(.down) * 5
    }

    /// Y-axis max using P95 to clip first-ping DNS spikes and other outliers.
    /// Returns at least chartYAxisMin + 10 so the chart never collapses to a sliver.
    var chartYAxisMax: Double {
        let times = successfulPings.map(\.time).sorted()
        guard let first = times.first else { return 10 }
        guard times.count >= 2 else { return max(first * 1.2, 10) }
        let p95Index = Int(Double(times.count - 1) * 0.95)
        let p95 = times[p95Index]
        let median = times[times.count / 2]
        let rawMax = max(p95, median * 1.5) * 1.15
        return max(rawMax, chartYAxisMin + 10)
    }
}
