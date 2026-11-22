import Foundation
import NetMonitorCore
import os

/// Saved speed tests on the Mac (#398). Results go to a JSON file rather than SwiftData,
/// so the versioned SwiftData schema stays unchanged.
@MainActor
enum MacSpeedTestHistory {
    static let store = SpeedTestHistoryStore(fileURL: SpeedTestHistoryStore.defaultFileURL())

    /// True while any speed test runs (manual or scheduled), so the two never overlap.
    static var isTestRunning = false

    static func record(_ data: SpeedTestData, at date: Date = Date(), store: SpeedTestHistoryStore = store) {
        store.append(SpeedTestHistoryEntry(
            timestamp: date,
            downloadMbps: data.downloadSpeed,
            uploadMbps: data.uploadSpeed,
            pingMs: data.latency
        ))
    }

    /// Deletes results older than the "Keep measurement history" setting (#395).
    static func prune(
        store: SpeedTestHistoryStore = store,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        guard let cutoff = HistoryRetention.current(in: defaults).cutoff(now: now) else { return }
        store.prune(olderThan: cutoff)
    }

    /// Runs one scheduled test with `service` and saves the result.
    static func runScheduledTest(service: any SpeedTestServiceProtocol, store: SpeedTestHistoryStore = store) async {
        guard !isTestRunning else { return }
        isTestRunning = true
        defer { isTestRunning = false }
        do {
            let data = try await service.startTest()
            record(data, store: store)
            prune(store: store)
            Logger.monitoring.notice("Scheduled speed test saved")
        } catch {
            Logger.monitoring.error("Scheduled speed test failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A scheduler that runs tests with its own `SpeedTestService` while the app is open.
    static func makeScheduler(service: any SpeedTestServiceProtocol = SpeedTestService()) -> ScheduledSpeedTestRunner {
        ScheduledSpeedTestRunner(
            lastRunAt: { store.entries().map(\.timestamp).max() },
            isRunning: { isTestRunning },
            runTest: { await runScheduledTest(service: service) }
        )
    }
}

/// Keeps saved speed tests within the retention setting while the app runs (#398, #395):
/// prunes at start, every `interval`, and whenever "Keep measurement history" changes.
/// It has its own timer because the hourly prune in `MonitoringSession` only runs while
/// monitoring is on.
@MainActor
final class SpeedTestHistoryMaintenance {
    private let store: SpeedTestHistoryStore
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async -> Void
    private let interval: Duration
    private var loopTask: Task<Void, Never>?
    private var defaultsObserver: (any NSObjectProtocol)?
    private var lastRetention: String?

    init(
        store: SpeedTestHistoryStore = MacSpeedTestHistory.store,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        interval: Duration = .seconds(3600)
    ) {
        self.store = store
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        self.interval = interval
    }

    func start() {
        guard loopTask == nil else { return }
        lastRetention = defaults.string(forKey: HistoryRetention.key)
        prune()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.retentionMayHaveChanged() }
        }
        let sleep = sleep
        let interval = interval
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await sleep(interval)
                guard !Task.isCancelled else { return }
                self?.prune()
            }
        }
    }

    func stop() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        defaultsObserver = nil
        loopTask?.cancel()
        loopTask = nil
    }

    /// Prunes when the retention value differs from the last one seen.
    func retentionMayHaveChanged() {
        let current = defaults.string(forKey: HistoryRetention.key)
        guard current != lastRetention else { return }
        lastRetention = current
        prune()
    }

    func prune() {
        MacSpeedTestHistory.prune(store: store, defaults: defaults, now: now())
    }
}
