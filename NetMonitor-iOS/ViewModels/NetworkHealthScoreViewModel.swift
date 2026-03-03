import Foundation
import NetMonitorCore

/// ViewModel for the Network Health Score dashboard card.
@MainActor
@Observable
final class NetworkHealthScoreViewModel {

    // MARK: - State

    var currentScore: NetworkHealthScore?
    var isCalculating: Bool = false
    var lastUpdated: Date?
    var errorMessage: String?

    // MARK: - Dependencies

    private let service: any NetworkHealthScoreServiceProtocol
    private let pingService: any PingServiceProtocol
    private let networkMonitor: any NetworkMonitorServiceProtocol
    private var currentTask: Task<Void, Never>?

    init(
        service: any NetworkHealthScoreServiceProtocol = NetworkHealthScoreService(),
        pingService: any PingServiceProtocol = PingService(),
        networkMonitor: any NetworkMonitorServiceProtocol = NetworkMonitorService()
    ) {
        self.service = service
        self.pingService = pingService
        self.networkMonitor = networkMonitor
    }

    // MARK: - Computed

    var gradeText: String { currentScore?.grade ?? "—" }
    var scoreValue: Int { currentScore?.score ?? 0 }

    var latencyText: String {
        guard let ms = currentScore?.latencyMs else { return "—" }
        return String(format: "%.0f ms", ms)
    }

    var packetLossText: String {
        guard let loss = currentScore?.packetLoss else { return "—" }
        return String(format: "%.0f%%", loss * 100)
    }

    // MARK: - Actions

    func refresh() {
        guard !isCalculating else { return }
        currentTask?.cancel()
        currentTask = Task { await performRefresh() }
    }

    // periphery:ignore
    func startAutoRefresh(interval: TimeInterval = 60) {
        currentTask?.cancel()
        currentTask = Task {
            while !Task.isCancelled {
                await performRefresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    // periphery:ignore
    func stopAutoRefresh() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Private

    private func performRefresh() async {
        isCalculating = true
        errorMessage = nil
        defer { isCalculating = false }

        var latencyMs: Double? = nil
        var packetLoss: Double? = nil

        let stream = await pingService.ping(host: "8.8.8.8", count: 5, timeout: 3)
        var results: [PingResult] = []
        for await result in stream {
            guard !Task.isCancelled else { break }
            results.append(result)
        }

        if !results.isEmpty {
            let successful = results.filter { !$0.isTimeout }
            latencyMs = successful.isEmpty ? nil : successful.map(\.time).reduce(0, +) / Double(successful.count)
            packetLoss = Double(results.count - successful.count) / Double(results.count)
        }

        if let svc = service as? NetworkHealthScoreService {
            svc.update(
                latencyMs: latencyMs,
                packetLoss: packetLoss,
                dnsResponseMs: nil,
                deviceCount: nil,
                typicalDeviceCount: nil,
                isConnected: networkMonitor.isConnected
            )
        }

        let score = await service.calculateScore()
        currentScore = score
        lastUpdated = Date()

        NetworkEventService.shared.log(
            type: .toolRun,
            title: "Health Score: \(score.grade) (\(score.score))",
            details: score.details["latency"].map { "Latency: \($0)" },
            severity: score.score >= 70 ? .success : (score.score >= 40 ? .warning : .error)
        )
    }
}
