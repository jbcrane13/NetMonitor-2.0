import Foundation
import NetworkScanKit
import Testing
@testable import NetMonitorCore

/// Waits until `condition` holds, at most `timeout`.
@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// #628 PR A: a device observation is saved only if no path update invalidated its token first.
@Suite("Join tokens")
@MainActor
struct JoinTokenTests {
    private func makeClock() -> NetworkJoinClock {
        let (changes, _) = AsyncStream<String>.makeStream()
        return NetworkJoinClock(changes: changes)
    }

    @Test func aTokenStaysCurrentWithoutAPathUpdate() {
        let clock = makeClock()
        let network = UUID()
        let token = clock.token(for: network)
        #expect(token.networkID == network)
        #expect(clock.isCurrent(token))
    }

    @Test func thePathTheAppStartedOnDoesNotInvalidate() {
        let clock = makeClock()
        let token = clock.token(for: nil)
        // The monitor's first report is the launch path, already covered by the clock's start.
        clock.generation.notePathUpdate()
        #expect(clock.isCurrent(token))
    }

    @Test func everyLaterPathUpdateInvalidatesEvenWithTheSameKey() {
        let clock = makeClock()
        clock.generation.notePathUpdate()
        let token = clock.token(for: nil)
        // Counted on the monitor's queue whatever the path key: a same-subnet move can keep it.
        clock.generation.notePathUpdate()
        #expect(!clock.isCurrent(token))
        let next = clock.token(for: nil)
        #expect(clock.isCurrent(next))
    }

    @Test func aResumeInvalidates() {
        let clock = makeClock()
        let token = clock.token(for: nil)
        clock.noteResume()
        #expect(!clock.isCurrent(token))
    }

    @Test func noTokenIsNeverCurrent() {
        #expect(!makeClock().isCurrent(nil))
    }

    @Test func aListFromBeforeThisLaunchIsNeverCurrent() {
        #expect(!makeClock().isCurrent(.unverified))
    }

    /// Lead review on #633: a token's network must still be where the device is at commit.
    @Test func aTokenForANetworkTheDeviceLeftIsNotCurrent() {
        let clock = makeClock()
        let home = UUID()
        var current = home
        clock.networkIsCurrent = { $0 == current }
        let token = clock.token(for: home)
        #expect(clock.isCurrent(token))
        current = UUID()
        #expect(!clock.isCurrent(token))
        #expect(clock.isCurrent(clock.token(for: nil)))
    }

    /// One guard for Ask's marker too: a scan establishes the network only with its token current.
    @Test func aScanEstablishesTheNetworkOnlyWithItsTokenCurrent() {
        let clock = makeClock()
        let token = clock.token(for: nil)
        clock.noteResume()
        clock.scanReconciled(token, at: Date(timeIntervalSince1970: 30))
        #expect(clock.establishedAt == nil)
        clock.scanReconciled(clock.token(for: nil), at: Date(timeIntervalSince1970: 60))
        #expect(clock.establishedAt == Date(timeIntervalSince1970: 60))
    }

    /// The counter is written on the path monitor's queue and read on the main actor.
    @Test func anUpdateFromAnotherThreadIsSeenAtTheNextCheck() async {
        let clock = makeClock()
        clock.generation.notePathUpdate()
        let token = clock.token(for: nil)
        let generation = clock.generation
        await Task.detached { generation.notePathUpdate() }.value
        #expect(!clock.isCurrent(token))
    }
}

@Suite("Replacement scans")
@MainActor
struct ReplacementScansTests {
    /// A sleep that returns when the test lets it.
    final class Gate: @unchecked Sendable {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private let lock = NSLock()
        var waiting: Int { lock.withLock { waiters.count } }

        func sleep() async {
            await withCheckedContinuation { continuation in
                lock.withLock { waiters.append(continuation) }
            }
        }

        func release() {
            let all = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                defer { waiters = [] }
                return waiters
            }
            all.forEach { $0.resume() }
        }
    }

    private func sleeping(_ gate: Gate) async {
        await waitUntil { gate.waiting > 0 }
    }

    @Test func aDroppedScanIsReplacedOnceThePathIsQuiet() async {
        let generation = JoinGeneration()
        let gate = Gate()
        let replacements = ReplacementScans(generation: generation) { _ in await gate.sleep() }
        var started = 0
        #expect(replacements.scanDropped { started += 1 })
        await sleeping(gate)
        gate.release()
        await waitUntil { started == 1 }
        #expect(started == 1)
    }

    @Test func itWaitsWhileThePathKeepsChanging() async {
        let generation = JoinGeneration()
        generation.notePathUpdate()
        let gate = Gate()
        let replacements = ReplacementScans(generation: generation) { _ in await gate.sleep() }
        var started = 0
        replacements.scanDropped { started += 1 }
        await sleeping(gate)
        generation.notePathUpdate()
        gate.release()
        // Another update arrived during the quiet period: it sleeps again instead of starting.
        await sleeping(gate)
        #expect(started == 0)
        gate.release()
        await waitUntil { started == 1 }
        #expect(started == 1)
    }

    @Test func atMostTwoAttemptsPerChainAndARawUpdateDoesNotReset() async {
        let generation = JoinGeneration()
        let gate = Gate()
        let replacements = ReplacementScans(generation: generation) { _ in await gate.sleep() }
        var started = 0
        for attempt in 1...2 {
            #expect(replacements.scanDropped { started += 1 })
            await sleeping(gate)
            gate.release()
            await waitUntil { started == attempt }
        }
        generation.notePathUpdate()
        generation.notePathUpdate()
        #expect(!replacements.scanDropped { started += 1 })
        #expect(started == 2)
    }

    @Test func aCommitStartsANewChain() async {
        let generation = JoinGeneration()
        let gate = Gate()
        let replacements = ReplacementScans(generation: generation) { _ in await gate.sleep() }
        var started = 0
        for attempt in 1...2 {
            replacements.scanDropped { started += 1 }
            await sleeping(gate)
            gate.release()
            await waitUntil { started == attempt }
        }
        replacements.reset()
        #expect(replacements.scanDropped { started += 1 })
        await sleeping(gate)
        gate.release()
        await waitUntil { started == 3 }
        #expect(started == 3)
    }

    /// Devin review on #633: a scan that saves while a replacement waits makes it unneeded.
    @Test func aResetCancelsAWaitingReplacement() {
        let generation = JoinGeneration()
        let replacements = ReplacementScans(generation: generation) { _ in try? await Task.sleep(for: .seconds(30)) }
        var started = 0
        replacements.scanDropped { started += 1 }
        replacements.reset()
        #expect(started == 0)
        #expect(replacements.attempts == 0)
        // A new chain can schedule again at once.
        #expect(replacements.scanDropped { started += 1 })
        #expect(replacements.attempts == 1)
    }

    @Test func dropsWhileOneIsPendingAreCoalesced() async {
        let generation = JoinGeneration()
        let gate = Gate()
        let replacements = ReplacementScans(generation: generation) { _ in await gate.sleep() }
        var started = 0
        replacements.scanDropped { started += 1 }
        replacements.scanDropped { started += 1 }
        await sleeping(gate)
        gate.release()
        await waitUntil { started == 1 }
        #expect(started == 1)
        #expect(replacements.attempts == 1)
    }
}

@Suite("Progressive latency")
struct ProgressiveLatencyTests {
    @Test func aLatencyFromTheRunningScanShowsForAnOnlineRowWithoutBeingSaved() {
        let network = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let row = LocalDevice(ipAddress: "192.168.1.20", macAddress: "00:11:22:33:44:55", status: .online, networkProfileID: network)
        row.lastLatency = 40
        let presence = PresenceSnapshot(lastScans: [network: now], now: now)
        #expect(presence.currentLatency(row) == 40)
        let progressive = presence.withProgressiveLatency([row.id: 3])
        #expect(progressive.currentLatency(row) == 3)
        #expect(row.lastLatency == 40)
    }

    @Test func anOfflineRowShowsNoLatency() {
        let network = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let row = LocalDevice(ipAddress: "192.168.1.20", macAddress: "", status: .offline, networkProfileID: network)
        let presence = PresenceSnapshot(lastScans: [network: now], now: now).withProgressiveLatency([row.id: 3])
        #expect(presence.currentLatency(row) == nil)
    }
}

/// #628 (lead review on #633): the iPhone's commit point. A scan whose token goes stale while it
/// runs is not published, cached or saved; its list and token go back to what they were.
@Suite("Discovery drops a stale scan", .serialized)
@MainActor
struct DiscoveryDropTests {
    /// Answers one device and, the first time, simulates a path update while it runs.
    private struct FixturePhase: ScanPhase, Sendable {
        let id: ScanPhaseID = "joinTokenFixture"
        let displayName = "Fixture"
        let weight: Double = 1.0
        let generation: JoinGeneration
        let changesPath: @Sendable () -> Bool

        func execute(context: ScanContext, accumulator: ScanAccumulator, onProgress: @Sendable (Double) async -> Void) async {
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: "192.0.2.20", hostname: "uitest-printer.local", vendor: "Brother", macAddress: "00:1B:A9:00:00:20",
                latency: 4, discoveredAt: Date(), source: .local
            ))
            if changesPath() {
                generation.notePathUpdate()
            }
            await onProgress(1)
        }
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = true
        func takeFirst() -> Bool {
            lock.withLock {
                defer { value = false }
                return value
            }
        }
    }

    @Test func aScanSpanningAPathUpdateIsDroppedAndTheNextIsPublished() async throws {
        let (changes, _) = AsyncStream<String>.makeStream()
        let clock = NetworkJoinClock(changes: changes)
        clock.generation.notePathUpdate()
        let generation = clock.generation
        let first = Flag()
        let defaults = try #require(UserDefaults(suiteName: "discovery-drop-\(UUID().uuidString)"))
        let service = DeviceDiscoveryService(userDefaults: defaults, joinClock: clock) { _, _ in
            ScanPipeline(steps: [ScanPipeline.Step(
                phases: [FixturePhase(generation: generation, changesPath: { first.takeFirst() })], concurrent: false
            )])
        }
        var drops = 0
        service.onScanDropped = { drops += 1 }

        await service.scanNetwork(subnet: "192.0.2")
        #expect(drops == 1)
        #expect(service.droppedScanCount == 1)
        #expect(service.lastScanDate == nil)
        #expect(service.completedScanDevices.isEmpty)
        #expect(service.discoveredDevices.isEmpty)
        #expect(service.discoveredDevicesToken == .unverified)

        await service.scanNetwork(subnet: "192.0.2")
        #expect(service.droppedScanCount == 1)
        #expect(service.lastScanDate != nil)
        #expect(service.completedScanDevices.map(\.ipAddress) == ["192.0.2.20"])
        #expect(clock.isCurrent(service.completedScanToken))
        #expect(clock.isCurrent(service.discoveredDevicesToken))
    }
}
