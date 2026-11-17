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
        let raw = defaults.string(forKey: "netmonitor.data.historyRetention") ?? HistoryRetention.sevenDays.rawValue
        guard let days = (HistoryRetention(rawValue: raw) ?? .sevenDays).days else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
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
