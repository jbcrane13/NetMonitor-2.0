import Foundation
import NetMonitorCore

/// Saves a health score for the Mac's network every 15 minutes while the app runs, so the
/// dashboard chart has a history even when nobody opens it (#491 D10). It scores through
/// `NetworkHealthScoreMacViewModel.refresh`, the same path as the dashboard card, which records
/// the sample; the history store throttles both to one sample per network per 15 minutes.
/// Each tick also prunes the history to the retention setting, since target monitoring (whose
/// hourly prune covers everything else) is usually off.
@MainActor
final class MacHealthSampler {
    static let interval: Duration = .seconds(15 * 60)
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let interval: Duration
    private let sleep: Sleep
    private let sample: @MainActor () async -> Void
    private let prune: @MainActor () -> Void
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - sleep: waits between samples; tests pass one that returns at once.
    ///   - prune: applies the retention setting to the history, before each sample.
    ///   - sample: takes one sample.
    init(
        interval: Duration = MacHealthSampler.interval,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        prune: @escaping @MainActor () -> Void = {},
        sample: @escaping @MainActor () async -> Void
    ) {
        self.interval = interval
        self.sleep = sleep
        self.prune = prune
        self.sample = sample
    }

    /// Samples the Mac's own network (the app's `profileManager`) through its own view model,
    /// only while the Mac is connected to it, and prunes the shared history.
    convenience init(profileManager: NetworkProfileManager) {
        let viewModel = NetworkHealthScoreMacViewModel()
        self.init(prune: { Self.pruneHealthHistory() }) {
            await viewModel.refresh(networkProfileID: profileManager.connectedLocalProfile?.id)
        }
    }

    /// Removes samples older than the history retention setting; "Forever" keeps them all.
    static func pruneHealthHistory(
        store: HealthScoreHistoryStore = .shared,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        guard let cutoff = HistoryRetention.current(in: defaults).cutoff(now: now) else { return }
        store.removeSamples(olderThan: cutoff)
    }

    /// Starts sampling now and every `interval`.
    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// Prunes and samples, then waits `interval`, until the sleep throws (cancellation).
    func run() async {
        while !Task.isCancelled {
            prune()
            await sample()
            do {
                try await sleep(interval)
            } catch {
                return
            }
        }
    }
}
