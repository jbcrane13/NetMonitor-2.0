import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// #628 PR A: a Mac scan is saved to device rows only if no path update or resume happened since
/// it started; a dropped scan writes nothing and schedules one replacement.
@MainActor
private func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Answers one device and simulates a path update while the scan runs.
private struct PathChangePhase: ScanPhase, Sendable {
    let id: ScanPhaseID = "joinTokenPathChange"
    let displayName = "Path change"
    let weight: Double = 1.0
    let generation: JoinGeneration

    func execute(context: ScanContext, accumulator: ScanAccumulator, onProgress: @Sendable (Double) async -> Void) async {
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "10.0.0.30", hostname: "printer", vendor: nil, macAddress: nil, latency: 4, discoveredAt: Date(), source: .local
        ))
        generation.notePathUpdate()
        await onProgress(1)
    }
}

@Suite("DeviceDiscoveryCoordinator join tokens (#628)", .serialized)
@MainActor
struct DeviceDiscoveryCoordinatorJoinTokenTests {
    private let home = UUID()
    private let base = DeviceDiscoveryCoordinatorReconcileTests()

    private func makeJoinClock() -> NetworkJoinClock {
        let (changes, _) = AsyncStream<String>.makeStream()
        let clock = NetworkJoinClock(changes: changes)
        // The monitor's first report: the path the app started on.
        clock.generation.notePathUpdate()
        return clock
    }

    @Test func aScanThatSpansAPathUpdateIsDroppedAndSavesNothing() throws {
        let (container, context) = try base.makeStore()
        _ = container
        let saved = LocalDevice(ipAddress: "10.0.0.20", macAddress: "", hostname: "living-room-tv", notes: "Mounted", networkProfileID: home)
        context.insert(saved)
        try context.save()
        let join = makeJoinClock()
        let coordinator = base.makeCoordinator(context, clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)), joinClock: join)

        let token = join.token(for: home)
        // The Mac moved while the scan ran: the next site has another device at that address.
        join.generation.notePathUpdate()
        let commit = coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.20", "kitchen-phone")],
            profileID: home, now: Date(timeIntervalSince1970: 1_790_000_060), token: token
        )

        #expect(commit == .dropped)
        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(rows.count == 1)
        #expect(rows.first?.hostname == "living-room-tv")
        #expect(rows.first?.notes == "Mounted")
        #expect(coordinator.lastScanTime(for: home) == nil)
        #expect(coordinator.replacementScans.attempts == 1)
    }

    @Test func aScanWithNoPathUpdateIsSavedAndStartsANewChain() throws {
        let (container, context) = try base.makeStore()
        _ = container
        let join = makeJoinClock()
        let coordinator = base.makeCoordinator(context, clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)), joinClock: join)

        let dropped = join.token(for: home)
        join.generation.notePathUpdate()
        _ = coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.21", "nas")], profileID: home,
            now: Date(timeIntervalSince1970: 1_790_000_030), token: dropped
        )
        #expect(coordinator.replacementScans.attempts == 1)

        let commit = coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.21", "nas")], profileID: home,
            now: Date(timeIntervalSince1970: 1_790_000_060), token: join.token(for: nil)
        )
        #expect(commit == .applied)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)
        #expect(coordinator.replacementScans.attempts == 0)
    }

    /// Lead review on #633: a token naming a network the Mac is no longer on (here, one its
    /// manager doesn't know) is not current even without a path update.
    @Test func aTokenForANetworkTheMacLeftDropsTheScan() throws {
        let (container, context) = try base.makeStore()
        _ = container
        let join = makeJoinClock()
        let coordinator = base.makeCoordinator(context, clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)), joinClock: join)
        let commit = coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.23", "tv")], profileID: home,
            now: Date(timeIntervalSince1970: 1_790_000_060), token: join.token(for: home)
        )
        #expect(commit == .dropped)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }

    @Test func aResumeDropsTheScan() throws {
        let (container, context) = try base.makeStore()
        _ = container
        let join = makeJoinClock()
        let coordinator = base.makeCoordinator(context, clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)), joinClock: join)
        let token = join.token(for: home)
        join.noteResume()
        let commit = coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.22", "printer")], profileID: home,
            now: Date(timeIntervalSince1970: 1_790_000_060), token: token
        )
        #expect(commit == .dropped)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }

    @Test func theSparseMergeLatencyIsClearedWhenTheScanStops() throws {
        let (container, context) = try base.makeStore()
        _ = container
        let mac = "AC:DE:48:00:00:B1"
        let row = LocalDevice(ipAddress: "10.0.0.70", macAddress: mac, hostname: "tv", networkProfileID: home)
        context.insert(row)
        try context.save()
        let coordinator = base.makeCoordinator(context, clock: TestClock(Date(timeIntervalSince1970: 1_790_000_000)), joinClock: makeJoinClock())
        coordinator.mergeSparseSnapshot([DeviceDiscoveryCoordinatorReconcileTests.device("10.0.0.70", nil, mac: mac, latency: 7)], profileID: home)
        #expect(coordinator.progressiveLatency[row.id] == 7)
        #expect(row.lastLatency == nil)
        coordinator.stopScan()
        #expect(coordinator.progressiveLatency.isEmpty)
    }

    /// Lead review on #633: a dropped scan leaves no trace: no last scan time, no review-prompt
    /// count, no profile scan info, no rows.
    @Test func aDroppedScanLeavesNoTrace() async throws {
        let (container, context) = try base.makeStore()
        _ = container
        let join = makeJoinClock()
        let generation = join.generation
        let defaults = try #require(UserDefaults(suiteName: "join-token-review-\(UUID().uuidString)"))
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(userDefaults: InMemoryDefaults(), activeProfilesProvider: { [] }),
            pipelineFactory: { _ in ScanPipeline(steps: [ScanPipeline.Step(phases: [PathChangePhase(generation: generation)], concurrent: false)]) },
            portChecker: { _, _, _ in false },
            reviewPrompt: ReviewPromptPolicy(defaults: defaults, requestReview: { false }),
            scanHistory: .forTesting(),
            dispatcher: DeviceEventDispatcher(),
            joinClock: join
        )

        coordinator.startScan()
        await waitUntil { !coordinator.isScanning }
        #expect(coordinator.lastScanTime == nil)
        #expect(defaults.integer(forKey: "reviewPrompt_completedScanCount") == 0)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
        #expect(coordinator.replacementScans.attempts == 1)
        coordinator.stopScan()
    }
}

@MainActor
extension NetworkJoinClock {
    /// A clock of the test's own (#628): the shared one counts this Mac's real path updates, which
    /// would drop a test's scans at random.
    static var forTests: NetworkJoinClock {
        NetworkJoinClock(changes: AsyncStream<String>.makeStream().stream)
    }
}
