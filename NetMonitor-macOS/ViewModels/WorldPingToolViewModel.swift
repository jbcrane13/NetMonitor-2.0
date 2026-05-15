import Foundation
import NetMonitorCore

/// ViewModel for the macOS World Ping tool.
@MainActor
@Observable
final class MacWorldPingToolViewModel {
    // MARK: - Input

    var hostInput: String = ""

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
        results.filter(\.isSuccess).count
    }

    // MARK: - Actions

    func run() {
        let host = hostInput.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !isRunning else { return }

        results.removeAll()
        errorMessage = nil
        isRunning = true

        runTask = Task { [runner] in
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
