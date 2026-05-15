import Foundation

// MARK: - WorldPingRunner

/// Encapsulates the duplicated run-and-accumulate loop that was previously
/// inlined in both `WorldPingToolViewModel` (iOS) and
/// `MacWorldPingToolViewModel` (macOS). Owns the `WorldPingServiceProtocol`
/// reference and the result-sorting policy; callers own the `Task` lifecycle
/// and the observable result array.
///
/// The runner is `Sendable` so it can be stored on `@MainActor @Observable`
/// VMs without isolation friction.
public struct WorldPingRunner: Sendable {
    public let service: any WorldPingServiceProtocol

    public init(service: any WorldPingServiceProtocol) {
        self.service = service
    }

    /// Streams the service's results, sorting the accumulator by ascending
    /// latency after each yield. Calls `onUpdate` on the @MainActor with the
    /// current sorted snapshot so the VM's `@Observable` array assignment
    /// triggers a SwiftUI redraw.
    ///
    /// Returns the final accumulated results, or a partial accumulation if
    /// the task is cancelled. Callers should check `Task.isCancelled` after
    /// `await` to decide whether to apply terminal state.
    @MainActor
    public func run(
        host: String,
        maxNodes: Int = 20,
        onUpdate: @MainActor (_ results: [WorldPingLocationResult]) -> Void
    ) async -> [WorldPingLocationResult] {
        var accumulated: [WorldPingLocationResult] = []
        let stream = await service.ping(host: host, maxNodes: maxNodes)
        for await result in stream {
            guard !Task.isCancelled else { break }
            accumulated.append(result)
            accumulated.sort { ($0.latencyMs ?? .infinity) < ($1.latencyMs ?? .infinity) }
            onUpdate(accumulated)
        }
        return accumulated
    }

    /// Convenience: pulls the trimmed `lastError` off the underlying service
    /// or returns a default empty-results message. Used by VMs when the
    /// stream finishes with no results.
    public func emptyResultsMessage(default: String = "No results returned. Check the host and your network connection.") -> String {
        service.lastError ?? `default`
    }
}
