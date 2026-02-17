import Foundation
import NetMonitorCore

/// ViewModel for the Ping tool view
@MainActor
@Observable
final class PingToolViewModel {
    // MARK: - Input Properties

    var host: String = ""
    var pingCount: Int = UserDefaults.standard.object(forKey: AppSettings.Keys.defaultPingCount) as? Int ?? 4

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
                results.append(result)
            }

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
}
