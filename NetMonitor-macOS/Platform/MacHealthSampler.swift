import Foundation
import NetMonitorCore

/// Saves a health score for the Mac's network every 15 minutes while the app runs, so the
/// dashboard chart has a history even when nobody opens it (#491 D10). It scores through
/// `NetworkHealthScoreMacViewModel.refresh`, the same path as the dashboard card, which records
/// the sample; the history store throttles both to one sample per network per 15 minutes.
@MainActor
final class MacHealthSampler {
    static let interval: Duration = .seconds(15 * 60)
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let interval: Duration
    private let sleep: Sleep
    private let sample: @MainActor () async -> Void
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - sleep: waits between samples; tests pass one that returns at once.
    ///   - sample: takes one sample.
    init(
        interval: Duration = MacHealthSampler.interval,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        sample: @escaping @MainActor () async -> Void
    ) {
        self.interval = interval
        self.sleep = sleep
        self.sample = sample
    }

    /// Samples the Mac's own network (the app's `profileManager`) through its own view model.
    convenience init(profileManager: NetworkProfileManager) {
        let viewModel = NetworkHealthScoreMacViewModel()
        self.init { await viewModel.refresh(networkProfileID: profileManager.localProfile?.id) }
    }

    /// Starts sampling now and every `interval`.
    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// Samples, then waits `interval`, until the sleep throws (cancellation).
    func run() async {
        while !Task.isCancelled {
            await sample()
            do {
                try await sleep(interval)
            } catch {
                return
            }
        }
    }
}
