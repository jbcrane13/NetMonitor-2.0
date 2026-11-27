import Foundation
import Testing
@testable import NetMonitorCore

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

    private func settle(_ gate: Gate) async {
        for _ in 0..<50 where gate.waiting == 0 {
            await Task.yield()
        }
    }

    private func drain() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    @Test func aDroppedScanIsReplacedOnceThePathIsQuiet() async {
        let generation = JoinGeneration()
        let gate = Gate()
        let replacements = ReplacementScans(generation: generation) { _ in await gate.sleep() }
        var started = 0
        #expect(replacements.scanDropped { started += 1 })
        await settle(gate)
        gate.release()
        await drain()
        #expect(started == 1)
    }

    @Test func itWaitsWhileThePathKeepsChanging() async {
        let generation = JoinGeneration()
        generation.notePathUpdate()
        let gate = Gate()
        let replacements = ReplacementScans(generation: generation) { _ in await gate.sleep() }
        var started = 0
        replacements.scanDropped { started += 1 }
        await settle(gate)
        generation.notePathUpdate()
        gate.release()
        await settle(gate)
        // Another update arrived during the quiet period: it waits again.
        #expect(started == 0)
        gate.release()
        await drain()
        #expect(started == 1)
    }

    @Test func atMostTwoAttemptsPerChainAndARawUpdateDoesNotReset() async {
        let generation = JoinGeneration()
        let gate = Gate()
        let replacements = ReplacementScans(generation: generation) { _ in await gate.sleep() }
        var started = 0
        for _ in 0..<2 {
            #expect(replacements.scanDropped { started += 1 })
            await settle(gate)
            gate.release()
            await drain()
        }
        generation.notePathUpdate()
        generation.notePathUpdate()
        #expect(!replacements.scanDropped { started += 1 })
        await drain()
        #expect(started == 2)
    }

    @Test func aCommitStartsANewChain() async {
        let generation = JoinGeneration()
        let gate = Gate()
        let replacements = ReplacementScans(generation: generation) { _ in await gate.sleep() }
        var started = 0
        for _ in 0..<2 {
            replacements.scanDropped { started += 1 }
            await settle(gate)
            gate.release()
            await drain()
        }
        replacements.reset()
        #expect(replacements.scanDropped { started += 1 })
        await settle(gate)
        gate.release()
        await drain()
        #expect(started == 3)
    }

    @Test func dropsWhileOneIsPendingAreCoalesced() async {
        let generation = JoinGeneration()
        let gate = Gate()
        let replacements = ReplacementScans(generation: generation) { _ in await gate.sleep() }
        var started = 0
        replacements.scanDropped { started += 1 }
        replacements.scanDropped { started += 1 }
        await settle(gate)
        gate.release()
        await drain()
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
