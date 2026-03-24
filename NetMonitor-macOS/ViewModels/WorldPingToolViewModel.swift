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
        results.filter(\.isSuccess).count
    }

    // MARK: - Actions

    func run() {
        let host = hostInput.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !isRunning else { return }

        results.removeAll()
        errorMessage = nil
        isRunning = true

        runTask = Task {
            let stream = await service.ping(host: host, maxNodes: 20)
            for await result in stream {
                guard !Task.isCancelled else { break }
                results.append(result)
                results.sort { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) }
            }

            guard !Task.isCancelled else { return }

            if results.isEmpty {
                errorMessage = service.lastError ?? "No results returned. Check the host and your network connection."
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
