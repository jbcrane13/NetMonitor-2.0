import Foundation
import Observation
import Testing
@testable import NetMonitorCore

/// #645 verification round: identification's remaining timing and recovery gaps.
extension NetworkIdentityControllerTests {
    /// Item 1: home (no hint) uses legacy L; at an IPv6 site on the same subnet the user made N. Back
    /// home, N doesn't win and home's scans aren't saved into it: both are offered.
    @Test func backHomeWithoutAHintANewSiteDoesNotWin() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .absent
        let identity = makeController(store, harness)
        #expect(identity.resolveID(group: home, defaultID: legacy) == legacy)

        harness.hint = .present(keyA)
        harness.probeAnswer = false
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        try identity.answer(.newNetwork, to: #require(identity.question))
        let siteN = identity.resolveID(group: home, defaultID: legacy)
        #expect(siteN != legacy)
        #expect(identity.authorizes(siteN))

        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: siteN)
        #expect(identity.question == .forgottenThisConnection(group: home, options: [siteN, legacy]))
        #expect(!identity.authorizes(siteN))
        #expect(!identity.authorizes(legacy))
    }

    /// Item 2: a detection that resolves to the same open question keeps it, and probes nothing again.
    @Test func anOpenQuestionSurvivesADetectionThatAsksTheSameThing() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.probeAnswer = false
        let identity = makeController(store, harness)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        let question = try #require(identity.question)
        _ = identity.resolveID(group: home, defaultID: legacy)
        #expect(identity.question == question)
        #expect(identity.probeTask == nil)
        #expect(harness.probes == 1)
    }

    /// Item 3: "keep this connection's network" on a failed read holds only within the generation it
    /// was identified under; after a path update a failed read holds and reads again.
    @Test func aFailedReadAfterAPathUpdateHoldsAndRetries() async throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        clock.generation.advance()
        harness.hint = .failed
        #expect(!identity.authorizes(siteA))
        _ = identity.resolveID(group: home, defaultID: siteA)
        #expect(!identity.authorizes(siteA))
        #expect(identity.heldNetworkIDs == [siteA])
        #expect(try #require(await eventually { harness.detections >= 1 }))
    }

    /// Item 8: a later successful detection with nothing held clears a failed save.
    @Test func aLaterSuccessfulDetectionClearsAFailedSave() throws {
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
        failing.fails = true
        try identity.answer(.same(siteA), to: #require(identity.question))
        #expect(identity.saveFailed)
        failing.fails = false
        harness.hint = .present(keyA)
        #expect(identity.resolveID(group: home, defaultID: siteA) == siteA)
        #expect(!identity.saveFailed)
    }

    /// Item 8: `isDamaged` is observable, so the paused card goes away after Start over.
    @Test func damageIsObservable() throws {
        let (_, dir, defaults) = try makeStore()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appending(path: NetworkIdentityStore.fileName))
        let damaged = NetworkIdentityStore(directory: dir, defaults: defaults, legacyNetworks: { [:] }, reservedIDs: { [] })
        let identity = makeController(damaged, Harness())
        final class Flag: @unchecked Sendable {
            var changed = false
        }
        let flag = Flag()
        withObservationTracking { _ = identity.isDamaged } onChange: { flag.changed = true }
        identity.startOver()
        #expect(!identity.isDamaged)
        #expect(flag.changed)
    }

    /// Item 9: a conflict while resolving re-resolves once against what the other copy saved.
    @Test func aConflictWhileResolvingReResolvesOnce() throws {
        let (store, dir, defaults) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let other = NetworkIdentityStore(directory: dir, defaults: defaults, legacyNetworks: { [:] }, reservedIDs: { [] })
        // The other copy identifies this router first.
        let otherIdentity = makeController(other, harness)
        let siteA = otherIdentity.resolveID(group: home, defaultID: UUID())
        let identity = makeController(store, harness)
        #expect(identity.resolveID(group: home, defaultID: UUID()) == siteA)
        #expect(identity.authorizes(siteA))
        #expect(!identity.saveFailed)
    }
}

extension NetworkIdentityStoreTests {
    /// Item 7: a "Somewhere else" bucket's rows are offered again after a start over.
    @Test func startOverOffersABucketsRows() throws {
        let env = try makeEnvironment()
        let store = store(env)
        let bucket = UUID()
        try store.update { $0.records.append(IdentityRecord(id: bucket, group: home, recordClass: .bucket)) }
        try Data("not json".utf8).write(to: env.dir.appending(path: NetworkIdentityStore.fileName))
        let damaged = self.store(env)
        try damaged.startOver()
        #expect(damaged.contents.records.contains { $0.id == bucket && $0.recordClass == .legacyUnverified })
    }

    /// Item 7: a forgotten network stays forgotten through a start over: offered, never quietly bound.
    @Test func startOverKeepsForgottenNetworksForgotten() throws {
        let env = try makeEnvironment()
        let store = store(env)
        let forgotten = UUID()
        try store.update { $0.records.append(IdentityRecord(id: forgotten, group: home, recordClass: .forgotten)) }
        try Data("not json".utf8).write(to: env.dir.appending(path: NetworkIdentityStore.fileName))
        let damaged = self.store(env)
        try damaged.startOver()
        #expect(damaged.contents.records.contains { $0.id == forgotten && $0.recordClass == .forgotten })
    }

    /// Item 7: a start over whose write fails leaves the damaged state as it was.
    @Test func aFailedStartOverLeavesTheOldState() throws {
        let env = try makeEnvironment()
        _ = store(env)
        try Data("not json".utf8).write(to: env.dir.appending(path: NetworkIdentityStore.fileName))
        struct Failure: Error {}
        let damaged = store(env) { _, _ in throw Failure() }
        #expect(throws: (any Error).self) { try damaged.startOver() }
        #expect(damaged.state == .damaged)
        #expect(env.defaults.bool(forKey: NetworkIdentityStore.damagedKey))
        #expect(env.defaults.bool(forKey: NetworkIdentityStore.markerKey))
        #expect(try Data(contentsOf: env.dir.appending(path: NetworkIdentityStore.fileName)) == Data("not json".utf8))
    }

    /// Item 9: a newer build's file pauses this build for this launch only; the newer build isn't paused.
    @Test func aNewerSchemaLeavesNoTombstone() throws {
        let env = try makeEnvironment()
        _ = store(env)
        let url = env.dir.appending(path: NetworkIdentityStore.fileName)
        let original = try Data(contentsOf: url)
        var json = try JSONSerialization.jsonObject(with: original) as? [String: Any] ?? [:]
        json["schemaVersion"] = NetworkIdentityStore.schemaVersion + 1
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        #expect(store(env).state == .newer)
        #expect(!env.defaults.bool(forKey: NetworkIdentityStore.damagedKey))
        try original.write(to: url)
        #expect(store(env).state == .ready, "the build that wrote it isn't paused")
    }

    /// Item 9: the lock is real: another holder of `flock` makes an update fail as a conflict after a
    /// bounded wait, instead of blocking.
    @Test func anotherHolderOfTheLockMakesAnUpdateConflict() throws {
        let env = try makeEnvironment()
        let store = store(env)
        let descriptor = open(env.dir.appending(path: "network-identity.lock").path, O_CREAT | O_RDWR, 0o600)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_EX) == 0)
        let start = Date()
        #expect(throws: NetworkIdentityStore.Conflict.self) {
            try store.update { $0.records.append(IdentityRecord(id: UUID(), group: home, recordClass: .bucket)) }
        }
        #expect(Date().timeIntervalSince(start) < 2)
    }
}
