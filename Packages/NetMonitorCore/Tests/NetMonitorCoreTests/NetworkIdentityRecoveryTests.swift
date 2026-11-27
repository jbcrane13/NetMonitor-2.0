import Foundation
import Testing
@testable import NetMonitorCore

/// #645 review: identification's timing and recovery.
extension NetworkIdentityControllerTests {
    /// #645: the router changes while the probe runs, with no path event: nothing is bound to the
    /// router the probe started under, and detection runs again.
    @Test func aRouterChangeDuringTheProbeBindsNothing() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.holdsProbe = true
        let identity = makeController(store, harness)
        _ = identity.resolveID(group: home, defaultID: legacy)
        try #require(await eventually { harness.probeGate != nil })
        harness.hint = .present(keyB)
        harness.probeGate?.resume()
        await identity.probeTask?.value
        #expect(store.contents.approvals.isEmpty)
        #expect(!identity.authorizes(legacy))
        #expect(harness.detections == 1)
        #expect(!identity.isStuckIdentifying)
    }

    /// #645: a path update invalidates the probe and detection runs before it finishes: identification
    /// starts again, and the network is identified once the new probe is clear.
    @Test func detectionDuringAnInvalidatedProbeStartsAnother() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.holdsProbe = true
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        _ = identity.resolveID(group: home, defaultID: legacy)
        try #require(await eventually { harness.probeGate != nil })
        let first = harness.probeGate
        harness.probeGate = nil
        clock.generation.advance()
        _ = identity.resolveID(group: home, defaultID: legacy)
        try #require(await eventually { harness.probeGate != nil })
        #expect(harness.probes == 2)
        // Identifying, with a probe running and no detection pending: not stuck (not vacuous).
        #expect(identity.isIdentifying)
        #expect(harness.detections == 0)
        #expect(!identity.isStuckIdentifying)
        let second = identity.probeTask
        harness.holdsProbe = false
        first?.resume()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(identity.probeTask != nil, "an obsolete probe doesn't clear the newer one")
        harness.probeGate?.resume()
        await second?.value
        #expect(identity.authorizes(legacy))
        #expect(!identity.isStuckIdentifying)
    }

    /// #645: an invalidated probe with no detection after it asks for one, so identifying never sticks.
    @Test func anInvalidatedProbeAsksForDetection() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.holdsProbe = true
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        _ = identity.resolveID(group: home, defaultID: legacy)
        try #require(await eventually { harness.probeGate != nil })
        clock.generation.advance()
        harness.holdsProbe = false
        harness.probeGate?.resume()
        await identity.probeTask?.value
        #expect(harness.detections == 1)
        #expect(!identity.isStuckIdentifying)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        #expect(identity.authorizes(legacy))
    }

    /// #645: a connection-only answer belongs to the connection its question was asked on.
    @Test func aConnectionOnlyAnswerAfterAPathUpdateIsRejected() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        try store.update { contents in
            contents.approvals.removeAll()
            if let index = contents.records.firstIndex(where: { $0.id == siteA }) {
                contents.records[index].recordClass = .forgotten
            }
        }
        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: siteA)
        let question = try #require(identity.question)
        clock.generation.advance()
        identity.answer(.thisConnection(siteA), to: question)
        #expect(store.contents.connectionAnswers.isEmpty)
        #expect(harness.detections == 1)
        _ = identity.resolveID(group: home, defaultID: siteA)
        #expect(identity.question == question, "the new connection is asked on its own")
        #expect(!identity.authorizes(siteA))
    }

    /// #645: a failed write keeps the question and says so; Retry saves it without a restart.
    @Test func aFailedAnswerWriteCanBeRetried() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "identity-\(UUID().uuidString)", directoryHint: .isDirectory)
        let defaults = try #require(UserDefaults(suiteName: "identity-\(UUID().uuidString)"))
        final class Switch {
            var fails = false
        }
        let failing = Switch()
        let store = NetworkIdentityStore(directory: dir, defaults: defaults, legacyNetworks: { [:] }, reservedIDs: { [] }) { data, url in
            if failing.fails {
                throw CocoaError(.fileWriteNoPermission)
            }
            try data.write(to: url, options: .atomic)
        }
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        harness.hint = .present(keyB)
        _ = identity.resolveID(group: home, defaultID: siteA)
        let question = try #require(identity.question)

        failing.fails = true
        identity.answer(.same(siteA), to: question)
        #expect(identity.saveFailed)
        #expect(identity.question == question, "the question stays answerable")
        #expect(!store.contents.approvals.contains { $0.key == keyB })
        #expect(harness.detections == 0)

        failing.fails = false
        identity.retrySave()
        #expect(!identity.saveFailed)
        #expect(store.contents.approvals.contains(IdentityApproval(group: home, key: keyB, recordID: siteA)))
        #expect(harness.detections == 1)
    }
}
