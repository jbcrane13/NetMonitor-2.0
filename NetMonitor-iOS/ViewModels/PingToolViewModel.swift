import Foundation
import NetMonitorCore

/// ViewModel for the Ping tool view
@MainActor
@Observable
final class PingToolViewModel {
    // MARK: - Input Properties

    var host: String = "" {
        didSet {
            let trimmed = host.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                TargetManager.shared.currentTarget = trimmed
            }
        }
    }

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

        let trimmed = host.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            TargetManager.shared.setTarget(trimmed)
        }

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

    /// Y-axis min for the chart. Always 0 so the AreaMark gradient renders
    /// correctly from the baseline and no data points clip below the axis.
    var chartYAxisMin: Double { 0 }

    /// Y-axis max: P95-clipped value with 20% padding, minimum 10ms ceiling so
    /// occasional spikes don't compress the chart scale for normal readings.
    var chartYAxisMax: Double {
        let times = successfulPings.map(\.time)
        guard times.count >= 2 else {
            return max((times.first ?? 0) * 1.2, 10)
        }
        let sorted = times.sorted()
        let p95Index = Int(Double(sorted.count - 1) * 0.95)
        let p95 = sorted[p95Index]
        return max(p95 * 1.2, 10)
    }
}
