import Foundation

/// Orchestrates scan phases according to a ``ScanPipeline``, tracking overall
/// progress and accumulating discovered devices.
public actor ScanEngine {
    /// The accumulator collecting all discovered devices.
    /// Declared `nonisolated` so callers can reference it without awaiting the actor.
    public nonisolated let accumulator: ScanAccumulator

    public init() {
        self.accumulator = ScanAccumulator()
    }

    /// Run a complete scan using the given pipeline and context.
    ///
    /// - Parameters:
    ///   - pipeline: Defines phase ordering and concurrency.
    ///   - context: Shared scan context (hosts, subnet filter, local IP).
    ///   - onProgress: Called with `(overallProgress, phaseDisplayName)` as scanning proceeds.
    /// - Returns: Sorted array of all discovered devices.
    /// Maximum time any single phase is allowed to run before being cancelled.
    /// Prevents a broken NWConnection / NECP state from hanging the entire pipeline.
    private static let phaseTimeout: Duration = .seconds(30)

    public func scan(
        pipeline: ScanPipeline,
        context: ScanContext,
        onProgress: @escaping @Sendable (Double, String) async -> Void
    ) async -> [DiscoveredDevice] {
        let totalWeight = pipeline.steps.flatMap(\.phases).reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return await accumulator.sortedSnapshot() }

        var completedWeight: Double = 0

        for step in pipeline.steps {
            let baseWeight = completedWeight

            if step.concurrent && step.phases.count > 1 {
                let accum = accumulator
                let timeout = Self.phaseTimeout
                await withTaskGroup(of: Void.self) { group in
                    for phase in step.phases {
                        let tw = totalWeight
                        let bw = baseWeight
                        group.addTask {
                            await Self.withTimeout(timeout) {
                                await phase.execute(context: context, accumulator: accum) { phaseProgress in
                                    let overall = (bw + phase.weight * phaseProgress) / tw
                                    await onProgress(overall, phase.displayName)
                                }
                            }
                        }
                    }
                }
                completedWeight = baseWeight + step.phases.reduce(0.0) { $0 + $1.weight }
            } else {
                for phase in step.phases {
                    let phaseBase = completedWeight
                    let tw = totalWeight
                    let timeout = Self.phaseTimeout
                    let accum = self.accumulator
                    await Self.withTimeout(timeout) {
                        await phase.execute(context: context, accumulator: accum) { phaseProgress in
                            let overall = (phaseBase + phase.weight * phaseProgress) / tw
                            await onProgress(overall, phase.displayName)
                        }
                    }
                    completedWeight += phase.weight
                }
            }
        }

        return await accumulator.sortedSnapshot()
    }

    /// Run an async operation with a timeout. If the operation exceeds the
    /// timeout, its task is cancelled and we move on.
    private static func withTimeout(_ duration: Duration, operation: @escaping @Sendable () async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(for: duration)
            }
            // When the first task completes (either operation finishes or timeout fires),
            // cancel the remaining one and return.
            await group.next()
            group.cancelAll()
        }
    }

    /// Reset the accumulator for a fresh scan.
    public func reset() async {
        await accumulator.reset()
    }
}
