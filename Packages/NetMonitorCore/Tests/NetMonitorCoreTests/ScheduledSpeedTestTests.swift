import Testing
import Foundation
@testable import NetMonitorCore

private func entry(_ date: Date, down: Double = 100) -> SpeedTestHistoryEntry {
    SpeedTestHistoryEntry(timestamp: date, downloadMbps: down, uploadMbps: 20, pingMs: 15)
}

@Suite("SpeedTestHistoryStore")
struct SpeedTestHistoryStoreTests {

    private func makeStore() -> SpeedTestHistoryStore {
        SpeedTestHistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("speedtest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.json"))
    }

    @Test func missingFileIsEmpty() {
        #expect(makeStore().entries().isEmpty)
    }

    @Test func appendRoundTripsThroughDisk() {
        let store = makeStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.append(entry(date, down: 250))
        store.append(entry(date.addingTimeInterval(60), down: 300))
        #expect(store.entries().map(\.downloadMbps) == [250, 300])
    }

    @Test func pruneDropsOnlyOlderEntries() {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.append(entry(now.addingTimeInterval(-10 * 86400)))
        store.append(entry(now.addingTimeInterval(-2 * 86400)))
        store.prune(olderThan: now.addingTimeInterval(-7 * 86400))
        #expect(store.entries().map(\.timestamp) == [now.addingTimeInterval(-2 * 86400)])
    }
}

@Suite("SpeedTestTrend")
struct SpeedTestTrendTests {

    @Test func keepsLastSevenDaysOldestFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [
            entry(now.addingTimeInterval(-3600)),
            entry(now.addingTimeInterval(-8 * 86400)),
            entry(now.addingTimeInterval(-6 * 86400)),
            entry(now.addingTimeInterval(60))
        ]
        let trend = SpeedTestTrend.lastSevenDays(entries, now: now)
        #expect(trend.map(\.timestamp) == [now.addingTimeInterval(-6 * 86400), now.addingTimeInterval(-3600)])
    }
}

/// Clock the tests move by hand.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(hours: Double) { lock.withLock { current = current.addingTimeInterval(hours * 3600) } }
}

@Suite("ScheduledSpeedTestRunner", .serialized)
@MainActor
struct ScheduledSpeedTestRunnerTests {

    @MainActor
    private final class Harness {
        let defaults: UserDefaults
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        var lastRun: Date?
        var running = false
        var runs = 0
        lazy var runner = ScheduledSpeedTestRunner(
            defaults: defaults,
            now: { [clock] in clock.now },
            sleep: { _ in try? await Task.sleep(for: .seconds(3600)) },
            lastRunAt: { [weak self] in self?.lastRun },
            isRunning: { [weak self] in self?.running ?? false },
            runTest: { [weak self] in
                guard let self else { return }
                runs += 1
                lastRun = clock.now
            }
        )

        init(hours: Int?) {
            let suite = "ScheduledSpeedTestRunnerTests-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suite) ?? .standard
            if let hours {
                defaults.set(hours, forKey: ScheduledSpeedTestRunner.intervalKey)
            }
        }
    }

    @Test func offByDefault() async {
        let harness = Harness(hours: nil)
        harness.runner.reload()
        #expect(harness.runner.activeIntervalHours == nil)
        #expect(await harness.runner.tick() == false)
        #expect(harness.runs == 0)
    }

    @Test func runsWhenNeverRunAndThenWaitsOneInterval() async {
        let harness = Harness(hours: 3)
        harness.runner.reload()
        #expect(await harness.runner.tick())
        #expect(await harness.runner.tick() == false)
        harness.clock.advance(hours: 2.9)
        #expect(await harness.runner.tick() == false)
        harness.clock.advance(hours: 0.2)
        #expect(await harness.runner.tick())
        #expect(harness.runs == 2)
        harness.runner.stop()
    }

    @Test func skipsWhileATestIsRunning() async {
        let harness = Harness(hours: 1)
        harness.runner.reload()
        harness.running = true
        #expect(await harness.runner.tick() == false)
        harness.running = false
        #expect(await harness.runner.tick())
        harness.runner.stop()
    }

    @Test func failedRunIsNotRetriedUntilNextInterval() async {
        let harness = Harness(hours: 6)
        let failing = ScheduledSpeedTestRunner(
            defaults: harness.defaults,
            now: { [clock = harness.clock] in clock.now },
            sleep: { _ in try? await Task.sleep(for: .seconds(3600)) },
            lastRunAt: { nil },
            isRunning: { false },
            runTest: {}
        )
        failing.reload()
        #expect(await failing.tick())
        harness.clock.advance(hours: 1)
        #expect(await failing.tick() == false)
        harness.clock.advance(hours: 5)
        #expect(await failing.tick())
        failing.stop()
    }

    @Test func turningScheduleOffStopsTimer() {
        let harness = Harness(hours: 12)
        harness.runner.reload()
        #expect(harness.runner.activeIntervalHours == 12)
        harness.defaults.set(0, forKey: ScheduledSpeedTestRunner.intervalKey)
        harness.runner.reload()
        #expect(harness.runner.activeIntervalHours == nil)
    }
}
