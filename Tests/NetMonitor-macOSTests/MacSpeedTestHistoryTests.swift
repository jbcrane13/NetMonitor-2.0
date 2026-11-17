import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_macOS

@Suite("MacSpeedTestHistory (#398)")
@MainActor
struct MacSpeedTestHistoryTests {

    private func makeStore() -> SpeedTestHistoryStore {
        SpeedTestHistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-speedtest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.json"))
    }

    private func makeDefaults(retention: String?) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "MacSpeedTestHistoryTests-\(UUID().uuidString)") ?? .standard
        if let retention {
            defaults.set(retention, forKey: "netmonitor.data.historyRetention")
        }
        return defaults
    }

    @Test func recordSavesDownloadUploadAndPing() {
        let store = makeStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        MacSpeedTestHistory.record(SpeedTestData(downloadSpeed: 310, uploadSpeed: 42, latency: 11), at: date, store: store)
        #expect(store.entries() == [SpeedTestHistoryEntry(timestamp: date, downloadMbps: 310, uploadMbps: 42, pingMs: 11)])
    }

    @Test func pruneFollowsHistoryRetentionSetting() {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let data = SpeedTestData(downloadSpeed: 100, uploadSpeed: 10, latency: 20)
        MacSpeedTestHistory.record(data, at: now.addingTimeInterval(-2 * 86400), store: store)
        MacSpeedTestHistory.record(data, at: now.addingTimeInterval(-3600), store: store)

        MacSpeedTestHistory.prune(store: store, defaults: makeDefaults(retention: "1 day"), now: now)
        #expect(store.entries().map(\.timestamp) == [now.addingTimeInterval(-3600)])
    }

    @Test func foreverRetentionKeepsEverything() {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        MacSpeedTestHistory.record(SpeedTestData(downloadSpeed: 1, uploadSpeed: 1, latency: 1), at: now.addingTimeInterval(-90 * 86400), store: store)
        MacSpeedTestHistory.prune(store: store, defaults: makeDefaults(retention: "Forever"), now: now)
        #expect(store.entries().count == 1)
    }

    @Test func scheduledRunSavesResultAndClearsRunningFlag() async {
        let store = makeStore()
        await MacSpeedTestHistory.runScheduledTest(service: NoOpSpeedTestService(), store: store)
        #expect(store.entries().count == 1)
        #expect(MacSpeedTestHistory.isTestRunning == false)
    }
}
