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

    // MARK: - Connection claim (#451 review)

    @Test func theClaimIsExclusiveSoTheToolAndTroubleshooterNeverOverlap() {
        #expect(MacSpeedTestHistory.testsRunning == 0)
        defer { while MacSpeedTestHistory.testsRunning > 0 { MacSpeedTestHistory.release() } }
        // The Speed Test tool claims: the troubleshooter (and a second claim of any kind) is refused.
        #expect(MacSpeedTestHistory.claim())
        #expect(!MacSpeedTestHistory.claim())
        #expect(MacSpeedTestHistory.isTestRunning)
        MacSpeedTestHistory.release()
        // The troubleshooter claims: the tool is refused until it releases.
        #expect(MacSpeedTestHistory.claim())
        #expect(!MacSpeedTestHistory.claim())
        MacSpeedTestHistory.release()
        #expect(MacSpeedTestHistory.claim())
    }

    @Test func releasingWithoutAClaimLeavesNothingNegative() {
        MacSpeedTestHistory.release()
        #expect(MacSpeedTestHistory.testsRunning == 0)
        #expect(!MacSpeedTestHistory.isTestRunning)
    }

    @Test func aScheduledRunIsRefusedWhileAnotherTestHoldsTheClaim() async {
        let store = makeStore()
        #expect(MacSpeedTestHistory.claim())
        await MacSpeedTestHistory.runScheduledTest(service: NoOpSpeedTestService(), store: store)
        #expect(store.entries().isEmpty)
        // A refused run must not release the holder's claim.
        #expect(MacSpeedTestHistory.isTestRunning)
        MacSpeedTestHistory.release()
        #expect(!MacSpeedTestHistory.isTestRunning)
    }

    // MARK: - Maintenance (#395 cleanup)

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func maintenancePrunesAtStart() {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        MacSpeedTestHistory.record(SpeedTestData(downloadSpeed: 1, uploadSpeed: 1, latency: 1), at: now.addingTimeInterval(-10 * 86400), store: store)
        let maintenance = SpeedTestHistoryMaintenance(
            store: store, defaults: makeDefaults(retention: "7 days"), now: { now },
            sleep: { _ in try? await Task.sleep(for: .seconds(3600)) }
        )
        maintenance.start()
        defer { maintenance.stop() }
        #expect(store.entries().isEmpty)
    }

    @Test func maintenancePrunesWhenRetentionChanges() async {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let defaults = makeDefaults(retention: "30 days")
        MacSpeedTestHistory.record(SpeedTestData(downloadSpeed: 1, uploadSpeed: 1, latency: 1), at: now.addingTimeInterval(-3 * 86400), store: store)
        let maintenance = SpeedTestHistoryMaintenance(
            store: store, defaults: defaults, now: { now },
            sleep: { _ in try? await Task.sleep(for: .seconds(3600)) }
        )
        maintenance.start()
        defer { maintenance.stop() }
        #expect(store.entries().count == 1)

        defaults.set("1 day", forKey: "netmonitor.data.historyRetention")
        await waitUntil { store.entries().isEmpty }
        #expect(store.entries().isEmpty)
    }

    @Test func maintenancePrunesOnItsPeriodicTimer() async {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let maintenance = SpeedTestHistoryMaintenance(
            store: store, defaults: makeDefaults(retention: "1 day"), now: { now },
            sleep: { _ in try? await Task.sleep(for: .milliseconds(20)) }
        )
        maintenance.start()
        defer { maintenance.stop() }
        // Added after start, so only the periodic prune can remove it.
        MacSpeedTestHistory.record(SpeedTestData(downloadSpeed: 1, uploadSpeed: 1, latency: 1), at: now.addingTimeInterval(-2 * 86400), store: store)
        await waitUntil { store.entries().isEmpty }
        #expect(store.entries().isEmpty)
    }
}
