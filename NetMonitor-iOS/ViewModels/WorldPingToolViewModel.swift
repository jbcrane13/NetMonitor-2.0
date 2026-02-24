import Foundation
import NetMonitorCore

/// ViewModel for the World Ping tool
@MainActor
@Observable
final class WorldPingToolViewModel {
    // MARK: - Input

    var hostInput: String = ""

    // MARK: - State

    var isRunning: Bool = false
    var results: [WorldPingLocationResult] = []
    var errorMessage: String?

    // MARK: - Dependencies

    private let service: any WorldPingServiceProtocol
    private var runTask: Task<Void, Never>?

    init(service: any WorldPingServiceProtocol = WorldPingService()) {
        self.service = service
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

        runTask = Task {
            let stream = await service.ping(
                host: hostInput.trimmingCharacters(in: .whitespaces),
                maxNodes: 20
            )

            for await result in stream {
                guard !Task.isCancelled else { break }
                results.append(result)
                results.sort { ($0.latencyMs ?? Double.infinity) < ($1.latencyMs ?? Double.infinity) }
            }

            guard !Task.isCancelled else { return }

            if results.isEmpty {
                errorMessage = "No results returned. Check the host address and your network connection."
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
