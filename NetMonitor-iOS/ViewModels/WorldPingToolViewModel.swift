import Foundation
import NetMonitorCore

/// ViewModel for the World Ping tool
@MainActor
@Observable
final class WorldPingToolViewModel {
    // MARK: - Input

    var hostInput: String = "" {
        didSet {
            let trimmed = hostInput.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                TargetManager.shared.currentTarget = trimmed
            }
        }
    }

    // MARK: - State

    var isRunning: Bool = false
    var results: [WorldPingLocationResult] = []
    var errorMessage: String?

    // MARK: - Dependencies

    private let runner: WorldPingRunner
    private var runTask: Task<Void, Never>?

    init(service: any WorldPingServiceProtocol = WorldPingService()) {
        self.runner = WorldPingRunner(service: service)
    }

    // MARK: - Computed

    var canRun: Bool {
        !hostInput.trimmingCharacters(in: .whitespaces).isEmpty && !isRunning
    }

    var hasResults: Bool { !results.isEmpty }

    var successCount: Int {
        results.filter { $0.isSuccess }.count
    }

    var averageLatencyMs: Double? {
        let latencies = results.compactMap { $0.latencyMs }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    var bestLatencyMs: Double? {
        results.compactMap { $0.latencyMs }.min()
    }

    // MARK: - Actions

    func run() {
        guard canRun else { return }
        results.removeAll()
        errorMessage = nil
        isRunning = true

        runTask = Task { [runner] in
            let host = hostInput.trimmingCharacters(in: .whitespaces)
            _ = await runner.run(host: host, maxNodes: 20) { sorted in
                results = sorted
            }
            guard !Task.isCancelled else { return }
            if results.isEmpty {
                errorMessage = runner.emptyResultsMessage()
            }
            isRunning = false
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
    }

    func clear() {
        stop()
        results.removeAll()
        errorMessage = nil
    }
}
