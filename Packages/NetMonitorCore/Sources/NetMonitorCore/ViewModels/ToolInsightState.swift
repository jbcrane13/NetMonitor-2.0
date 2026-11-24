import Foundation

/// Shared state for the "Explain" affordance under a tool result on macOS and iOS (#448).
@MainActor
@Observable
public final class ToolInsightState {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The explanation so far; empty until the first words arrive.
        case generating(String)
        case finished(String)
        case failed
    }

    public private(set) var phase: Phase = .idle
    /// Who writes the current explanation: this device, or the connected Mac (#457).
    public private(set) var source: InsightSource = .device

    private let service: any InsightServiceProtocol
    private var task: Task<Void, Never>?
    /// The request `phase` belongs to.
    private var explained: InsightRequest?
    /// Identifies the current explanation, so a replaced or reset one can't write its text.
    private var generation = 0

    public init(service: any InsightServiceProtocol = InsightService.shared) {
        self.service = service
    }

    /// Whether to show the affordance at all.
    public var isAvailable: Bool { service.isAvailable }

    /// The phase to show under `request`: idle unless `request` is the one being explained,
    /// so an explanation never sits under a result it does not describe.
    public func phase(for request: InsightRequest) -> Phase {
        request == explained ? phase : .idle
    }

    /// Explains `request`, replacing any explanation in progress.
    @discardableResult
    public func explain(_ request: InsightRequest) -> Task<Void, Never> {
        task?.cancel()
        generation += 1
        guard service.isAvailable else {
            phase = .idle
            return Task {}
        }
        phase = .generating("")
        source = InsightService.source(of: service)
        explained = request
        let current = generation
        let service = service
        let task = Task { [weak self] in
            var ended = false
            for await update in service.explain(request) {
                guard let self, self.generation == current else { return }
                switch update {
                case let .partial(text): self.phase = .generating(text)
                case let .finished(text): self.phase = .finished(text)
                    ended = true
                // A Mac that was busy or went away (#457) also ends here: Try Again asks anew.
                case .failed, .unreachable: self.phase = .failed
                    ended = true
                }
            }
            if !ended, let self, self.generation == current {
                self.phase = .failed
            }
        }
        self.task = task
        return task
    }

    /// Clears the explanation, for when the result it described is replaced.
    public func reset() {
        task?.cancel()
        generation += 1
        phase = .idle
        explained = nil
    }
}
