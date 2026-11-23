import Foundation
import NetMonitorCore
import Observation
import SwiftData
import Testing
@testable import NetMonitor_macOS

// MARK: - Health-score history on macOS (#491 S5)

private final class AnsweringPingService: PingServiceProtocol, @unchecked Sendable {
    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        AsyncStream { continuation in
            continuation.yield(PingResult(sequence: 1, host: host, ttl: 64, time: 12, isTimeout: false))
            continuation.finish()
        }
    }

    func stop() async {}
    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? { nil }
}

/// Records each wait, and stops the loop after `limit` of them.
private final class RecordingSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var _durations: [Duration] = []
    let limit: Int
    init(limit: Int) { self.limit = limit }

    var durations: [Duration] { lock.withLock { _durations } }

    func sleep(_ duration: Duration) throws {
        let count = lock.withLock {
            _durations.append(duration)
            return _durations.count
        }
        if count >= limit {
            throw CancellationError()
        }
    }
}

private final class RedrawFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

@Suite("NetworkHealthScoreMacViewModel history")
@MainActor
struct HealthScoreMacVMHistoryTests {
    let network = UUID()

    func makeVM(store: HealthScoreHistoryStore) -> NetworkHealthScoreMacViewModel {
        NetworkHealthScoreMacViewModel(pingService: AnsweringPingService(), readDNSServers: { .unavailable }, historyStore: store)
    }

    @Test func refreshSavesASampleForTheGivenNetwork() async throws {
        let store = HealthScoreHistoryStore()
        let vm = makeVM(store: store)
        await vm.refresh(networkProfileID: network)
        let score = try #require(vm.currentScore)
        #expect(store.samples(for: network).map(\.score) == [score.score])
        #expect(vm.history.count == 1)
        #expect(!vm.showsHistoryChart)
    }

    @Test func secondRefreshInsideFifteenMinutesIsThrottled() async {
        let store = HealthScoreHistoryStore()
        let vm = makeVM(store: store)
        await vm.refresh(networkProfileID: network)
        await vm.refresh(networkProfileID: network)
        #expect(store.samples(for: network).count == 1)
    }

    @Test func chartShowsOnceThereAreTwoSamples() async {
        let store = HealthScoreHistoryStore()
        store.record(NetworkHealthScore(score: 40, grade: "F"), networkProfileID: network, at: Date().addingTimeInterval(-7200))
        let vm = makeVM(store: store)
        await vm.refresh(networkProfileID: network)
        #expect(vm.history.first?.score == 40)
        #expect(vm.history.count == 2)
        #expect(vm.showsHistoryChart)
    }

    @Test func noNetworkMeansNoSample() async {
        let store = HealthScoreHistoryStore()
        let vm = makeVM(store: store)
        await vm.refresh()
        #expect(store.samples(for: network).isEmpty)
        #expect(vm.history.isEmpty)
    }

    /// The 15-minute sampler has its own view model; the dashboard's chart must still redraw.
    @Test func dashboardChartUpdatesWhenTheSamplerRecords() async {
        let store = HealthScoreHistoryStore()
        store.record(NetworkHealthScore(score: 40, grade: "F"), networkProfileID: network, at: Date().addingTimeInterval(-7200))
        let dashboard = makeVM(store: store)
        await dashboard.refresh(networkProfileID: network)
        #expect(dashboard.history.count == 2)

        let redrawn = RedrawFlag()
        withObservationTracking {
            _ = dashboard.showsHistoryChart
        } onChange: {
            redrawn.set()
        }
        // The sampler's next tick, through its own view model and the same store.
        store.record(NetworkHealthScore(score: 90, grade: "A"), networkProfileID: network, at: Date().addingTimeInterval(3600))
        #expect(redrawn.isSet)
        #expect(dashboard.history.map(\.score).last == 90)
    }
}

@Suite("MacHealthSampler")
@MainActor
struct MacHealthSamplerTests {
    @Test func samplesAtStartThenEveryFifteenMinutes() async {
        let sleeper = RecordingSleep(limit: 3)
        var samples = 0
        let sampler = MacHealthSampler(sleep: { try sleeper.sleep($0) }, sample: { samples += 1 })
        await sampler.run()
        #expect(samples == 3)
        #expect(sleeper.durations == [.seconds(900), .seconds(900), .seconds(900)])
    }

    @Test func timerSamplesAreSavedThroughTheViewModel() async {
        let network = UUID()
        let store = HealthScoreHistoryStore()
        let vm = NetworkHealthScoreMacViewModel(pingService: AnsweringPingService(), readDNSServers: { .unavailable }, historyStore: store)
        let sleeper = RecordingSleep(limit: 1)
        await MacHealthSampler(sleep: { try sleeper.sleep($0) }, sample: { await vm.refresh(networkProfileID: network) }).run()
        #expect(store.samples(for: network).count == 1)
    }
}

@Suite("UITestHealthHistory")
@MainActor
struct UITestHealthHistoryTests {
    @Test func seedsOnlyWhenAsked() {
        let network = UUID()
        let store = HealthScoreHistoryStore()
        UITestHealthHistory.seedIfRequested(networkProfileID: network, arguments: ["app"], store: store)
        #expect(store.samples(for: network).isEmpty)
        UITestHealthHistory.seedIfRequested(networkProfileID: network, arguments: ["app", "--seed-health-samples"], store: store)
        #expect(store.samples(for: network).map(\.score) == HealthScoreHistoryStore.uiTestSeedScores.map(\.score))
    }
}

@Suite("History retention: health samples (macOS)")
@MainActor
struct HealthHistoryRetentionTests {
    @Test func pruneRemovesOldHealthSamples() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let suite = RetentionSuite("7 days")
        defer { suite.clear() }
        let network = UUID()
        let store = HealthScoreHistoryStore()
        store.record(NetworkHealthScore(score: 30, grade: "F"), networkProfileID: network, at: now.addingTimeInterval(-10 * 86400))
        store.record(NetworkHealthScore(score: 95, grade: "A"), networkProfileID: network, at: now.addingTimeInterval(-86400))

        MonitoringSession(modelContext: container.mainContext, defaults: suite.defaults)
            .pruneOldMeasurements(eventService: NetworkEventService(), healthHistory: store, now: now)

        #expect(store.samples(for: network).map(\.score) == [95])
    }
}
