import Foundation
import SwiftData
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

// MARK: - Health-score history on iOS (#491 S5)

private final class FixedHealthScoreService: NetworkHealthScoreServiceProtocol, @unchecked Sendable {
    var score = NetworkHealthScore(score: 84, grade: "B", latencyMs: 20, packetLoss: 0, details: ["latency": "20 ms"])
    func update(latencyMs: Double?, packetLoss: Double?, dnsResponseMs: Double?, deviceCount: Int?, typicalDeviceCount: Int?, isConnected: Bool) {}
    func calculateScore() async -> NetworkHealthScore { score }
}

/// Never answers: its stream ends only when the consuming task is cancelled.
private final class HangingPingService: PingServiceProtocol, @unchecked Sendable {
    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        AsyncStream { _ in }
    }

    func stop() async {}
    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? { nil }
}

@MainActor
private func makeProbe(score: Int = 84) -> HealthSampleProbe {
    let service = FixedHealthScoreService()
    service.score = NetworkHealthScore(score: score, grade: "B")
    let ping = MockPingService()
    ping.mockResults = [PingResult(sequence: 1, host: "8.8.8.8", ttl: 64, time: 20, isTimeout: false)]
    return HealthSampleProbe(service: service, pingService: ping, networkMonitor: MockNetworkMonitorService())
}

@Suite("NetworkHealthScoreViewModel history")
@MainActor
struct NetworkHealthScoreViewModelHistoryTests {
    let network = UUID()

    func makeVM(store: HealthScoreHistoryStore, networkID: UUID?) -> NetworkHealthScoreViewModel {
        let service = FixedHealthScoreService()
        let ping = MockPingService()
        ping.mockResults = [PingResult(sequence: 1, host: "8.8.8.8", ttl: 64, time: 20, isTimeout: false)]
        return NetworkHealthScoreViewModel(
            service: service,
            pingService: ping,
            networkMonitor: MockNetworkMonitorService(),
            historyStore: store,
            currentNetworkProfileID: { networkID }
        )
    }

    @Test func refreshSavesASampleForTheCurrentNetwork() async {
        let store = HealthScoreHistoryStore()
        let vm = makeVM(store: store, networkID: network)
        vm.refresh()
        await waitUntil { vm.lastUpdated != nil && !vm.isCalculating }
        #expect(store.samples(for: network).map(\.score) == [84])
        #expect(vm.history.map(\.score) == [84])
    }

    @Test func noNetworkMeansNoSample() async {
        let store = HealthScoreHistoryStore()
        let vm = makeVM(store: store, networkID: nil)
        vm.refresh()
        await waitUntil { vm.lastUpdated != nil && !vm.isCalculating }
        #expect(store.samples(for: network).isEmpty)
        #expect(vm.history.isEmpty)
        #expect(!vm.showsHistoryChart)
    }

    @Test func chartIsHiddenBelowTwoSamples() async {
        let store = HealthScoreHistoryStore()
        let vm = makeVM(store: store, networkID: network)
        vm.refresh()
        await waitUntil { vm.lastUpdated != nil && !vm.isCalculating }
        #expect(vm.history.count == 1)
        #expect(!vm.showsHistoryChart)
    }

    @Test func chartShowsWithTwoSamples() async {
        let store = HealthScoreHistoryStore()
        store.record(NetworkHealthScore(score: 60, grade: "D"), networkProfileID: network, at: Date().addingTimeInterval(-3600))
        let vm = makeVM(store: store, networkID: network)
        vm.refresh()
        await waitUntil { vm.lastUpdated != nil && !vm.isCalculating }
        #expect(vm.history.map(\.score) == [60, 84])
        #expect(vm.showsHistoryChart)
    }

    @Test func cancelledRefreshSavesNothing() async {
        let store = HealthScoreHistoryStore()
        let network = network
        let vm = NetworkHealthScoreViewModel(
            service: FixedHealthScoreService(),
            pingService: HangingPingService(),
            networkMonitor: MockNetworkMonitorService(),
            historyStore: store,
            currentNetworkProfileID: { network }
        )
        vm.refresh()
        await waitUntil { vm.isCalculating }
        vm.stopAutoRefresh()
        await waitUntil { !vm.isCalculating }
        #expect(store.samples(for: network).isEmpty)
    }

    @Test func refreshNoLongerLogsAHealthEvent() async {
        let before = NetworkEventService.shared.events.filter { $0.title.hasPrefix("Health Score") }.count
        let vm = makeVM(store: HealthScoreHistoryStore(), networkID: network)
        vm.refresh()
        await waitUntil { vm.lastUpdated != nil && !vm.isCalculating }
        #expect(NetworkEventService.shared.events.filter { $0.title.hasPrefix("Health Score") }.count == before)
    }
}

@Suite("BackgroundTaskService health sample")
@MainActor
struct BackgroundHealthSampleTests {
    let network = UUID()

    func makeFileStore() throws -> (HealthScoreHistoryStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bg-health-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: HealthScoreHistoryStore.fileName)
        // A debounce far longer than the test: only a flush can have saved it.
        return (HealthScoreHistoryStore(fileURL: url, debounce: 3600), url)
    }

    @Test func sampleIsSavedToDiskBeforeTheTaskCompletes() async throws {
        let (store, url) = try makeFileStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = ScheduledRequestRecorder().makeService()
        await service.recordHealthSample(probe: makeProbe(score: 73), store: store, networkProfileID: network, isCancelled: { false })
        // What the refresh task's completion would see on disk right after this returns.
        let savedAtCompletion = HealthScoreHistoryStore(fileURL: url).samples(for: network).map(\.score)
        #expect(savedAtCompletion == [73])
    }

    @Test func noLocalNetworkTakesNoSample() async throws {
        let (store, url) = try makeFileStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = ScheduledRequestRecorder().makeService()
        await service.recordHealthSample(probe: makeProbe(), store: store, networkProfileID: nil, isCancelled: { false })
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func cancelledTaskSavesNothing() async throws {
        let (store, url) = try makeFileStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = ScheduledRequestRecorder().makeService()
        await service.recordHealthSample(probe: makeProbe(), store: store, networkProfileID: network, isCancelled: { true })
        #expect(store.samples(for: network).isEmpty)
    }
}

@Suite("Clear all data: health history")
@MainActor
struct ClearAllDataHealthHistoryTests {
    @Test func clearAllCachedDataClearsHealthHistory() async throws {
        let schema = Schema([LocalDevice.self, MonitoringTarget.self, ToolResult.self, SpeedTestResult.self, PairedMac.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        defer { withExtendedLifetime(container) {} }
        let network = UUID()
        let store = HealthScoreHistoryStore()
        store.record(NetworkHealthScore(score: 70, grade: "C"), networkProfileID: network)
        await SettingsViewModel(healthHistory: store).clearAllCachedData(modelContext: container.mainContext)
        #expect(store.samples(for: network).isEmpty)
    }
}

@Suite("DataMaintenanceService health pruning")
@MainActor
struct DataMaintenanceHealthPruneTests {
    @Test func prunesHealthSamplesPastRetention() throws {
        let network = UUID()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let store = HealthScoreHistoryStore()
        store.record(NetworkHealthScore(score: 40, grade: "F"), networkProfileID: network, at: now.addingTimeInterval(-40 * 86400))
        store.record(NetworkHealthScore(score: 90, grade: "A"), networkProfileID: network, at: now.addingTimeInterval(-86400))
        let suite = "health-prune-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(30, forKey: AppSettings.Keys.dataRetentionDays)
        let schema = Schema([ToolResult.self, SpeedTestResult.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        DataMaintenanceService.pruneExpiredData(
            modelContext: container.mainContext, defaults: defaults,
            eventService: NetworkEventService(), healthHistory: store, now: now
        )
        #expect(store.samples(for: network).map(\.score) == [90])
    }
}

private final class ConnectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _profiles: [NetworkProfile]
    init(profiles: [NetworkProfile]) { _profiles = profiles }
    var profiles: [NetworkProfile] {
        get { lock.withLock { _profiles } }
        set { lock.withLock { _profiles = newValue } }
    }
}

@Suite("HealthSampleProbe network")
@MainActor
struct HealthSampleProbeNetworkTests {
    func makeDefaults() -> UserDefaults {
        let suite = "health-probe-\(UUID())"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// This device's network, as `NetworkProfileManager` detects it.
    func detectedLocalProfile() -> NetworkProfile {
        let network = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A8_0100, broadcastAddress: 0xC0A8_01FF, interfaceAddress: 0xC0A8_010A, netmask: 0xFFFF_FF00
        )
        return NetworkProfile(
            id: UUID(), interfaceName: "en0", ipAddress: "192.168.1.10",
            network: network, connectionType: .wifi, name: "WiFi", gatewayIP: "192.168.1.1",
            subnet: "192.168.1.0/24", isLocal: true, discoveryMethod: .auto
        )
    }

    @Test func aManualActiveNetworkIsNeverSampled() throws {
        let manager = NetworkProfileManager(userDefaults: makeDefaults(), activeProfilesProvider: { [] })
        let manual = try #require(manager.addProfile(gateway: "10.9.0.1", subnet: "10.9.0.0/24", name: "Office"))
        #expect(manager.switchProfile(id: manual.id))
        #expect(manager.activeProfile?.id == manual.id)
        #expect(HealthSampleProbe.localNetworkProfileID(in: manager) == nil)
    }

    /// After a disconnect the saved local profile lingers; an offline score must not be filed
    /// under it.
    @Test func noSamplesAfterThisDeviceDisconnects() throws {
        let local = detectedLocalProfile()
        let connected = ConnectionBox(profiles: [local])
        let manager = NetworkProfileManager(userDefaults: makeDefaults(), activeProfilesProvider: { connected.profiles })
        #expect(HealthSampleProbe.localNetworkProfileID(in: manager) == manager.localProfile?.id)
        connected.profiles = []
        #expect(manager.localProfile != nil)
        #expect(HealthSampleProbe.localNetworkProfileID(in: manager) == nil)
    }

    @Test func samplesGoToThisDevicesNetworkWhileAnotherIsActive() throws {
        let local = detectedLocalProfile()
        let manager = NetworkProfileManager(userDefaults: makeDefaults(), activeProfilesProvider: { [local] })
        let localID = try #require(manager.localProfile?.id)
        let manual = try #require(manager.addProfile(gateway: "10.9.0.1", subnet: "10.9.0.0/24", name: "Office"))
        #expect(manager.switchProfile(id: manual.id))
        #expect(HealthSampleProbe.localNetworkProfileID(in: manager) == localID)
    }
}
