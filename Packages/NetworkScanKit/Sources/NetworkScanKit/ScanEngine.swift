import Foundation

private actor ScanTimeoutRace {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isResolved = false

    func wait() async {
        guard !isResolved else { return }
        await withCheckedContinuation { continuation in
            guard !isResolved else {
                continuation.resume()
                return
            }
            self.continuation = continuation
        }
    }

    func resolve() {
        guard !isResolved else { return }
        isResolved = true
        continuation?.resume()
        continuation = nil
    }
}

/// Orchestrates scan phases according to a ``ScanPipeline``, tracking overall
/// progress and accumulating discovered devices.
public actor ScanEngine {
    /// The accumulator collecting all discovered devices.
    /// Declared `nonisolated` so callers can reference it without awaiting the actor.
    nonisolated public let accumulator: ScanAccumulator

    private let phaseTimeout: Duration

    public init(phaseTimeout: Duration = .seconds(30)) {
        self.accumulator = ScanAccumulator()
        self.phaseTimeout = phaseTimeout
    }

    /// Run a complete scan using the given pipeline and context.
    ///
    /// - Parameters:
    ///   - pipeline: Defines phase ordering and concurrency.
    ///   - context: Shared scan context (hosts, subnet filter, local IP).
    ///   - onProgress: Called with `(overallProgress, phaseID)` as scanning proceeds.
    /// - Returns: Sorted array of all discovered devices.
    public func scan(
        pipeline: ScanPipeline,
        context: ScanContext,
        onProgress: @escaping @Sendable (Double, ScanPhaseID) async -> Void
    ) async -> [DiscoveredDevice] {
        guard !Task.isCancelled else { return await accumulator.sortedSnapshot() }
        let totalWeight = pipeline.steps.flatMap(\.phases).reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return await accumulator.sortedSnapshot() }

        var completedWeight: Double = 0

        for step in pipeline.steps {
            guard !Task.isCancelled else { break }
            let baseWeight = completedWeight

            if step.concurrent && step.phases.count > 1 {
                let accum = accumulator
                let defaultTimeout = phaseTimeout
                await withTaskGroup(of: Void.self) { group in
                    for phase in step.phases {
                        guard !Task.isCancelled else { break }
                        let tw = totalWeight
                        let bw = baseWeight
                        let timeout = phase.timeout ?? defaultTimeout
                        group.addTask {
                            await Self.withTimeout(timeout) {
                                await phase.execute(context: context, accumulator: accum) { phaseProgress in
                                    guard !Task.isCancelled else { return }
                                    let overall = (bw + phase.weight * phaseProgress) / tw
                                    await onProgress(overall, phase.id)
                                }
                            }
                        }
                    }
                }
                guard !Task.isCancelled else { break }
                completedWeight = baseWeight + step.phases.reduce(0.0) { $0 + $1.weight }
            } else {
                for phase in step.phases {
                    guard !Task.isCancelled else { break }
                    let phaseBase = completedWeight
                    let tw = totalWeight
                    let timeout = phase.timeout ?? phaseTimeout
                    let accum = self.accumulator
                    await Self.withTimeout(timeout) {
                        await phase.execute(context: context, accumulator: accum) { phaseProgress in
                            guard !Task.isCancelled else { return }
                            let overall = (phaseBase + phase.weight * phaseProgress) / tw
                            await onProgress(overall, phase.id)
                        }
                    }
                    guard !Task.isCancelled else { break }
                    completedWeight += phase.weight
                }
            }
        }

        return await accumulator.sortedSnapshot()
    }

    /// Run an async operation with a timeout. If the operation exceeds the
    /// timeout, its task is cancelled and we move on.
    private static func withTimeout(_ duration: Duration, operation: @escaping @Sendable () async -> Void) async {
        let race = ScanTimeoutRace()
        let operationTask = Task {
            await operation()
            await race.resolve()
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: duration)
                await race.resolve()
            } catch {
                return
            }
        }

        await withTaskCancellationHandler {
            await race.wait()
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            Task { await race.resolve() }
        }

        operationTask.cancel()
        timeoutTask.cancel()
    }

    /// Reset the accumulator for a fresh scan.
    public func reset() async {
        await accumulator.reset()
    }
}
