import Foundation
import Testing
@testable import NetMonitorCore

/// #645 round 4: the no-hint approval (lead decision) and the low items.
extension NetworkIdentityControllerTests {
    /// Home on legacy L with no hint, bound N elsewhere: one question at home, answered L; after a
    /// path update home is L with no question; at N's site (hint present) it's N.
    @Test func homeWithoutAHintIsAskedOnceThenRemembered() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.probeAnswer = false
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        try identity.answer(.newNetwork, to: #require(identity.question))
        let siteN = identity.resolveID(group: home, defaultID: legacy)

        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: siteN)
        let question = try #require(identity.question)
        identity.answer(.thisConnection(legacy), to: question)
        #expect(identity.resolveID(group: home, defaultID: siteN) == legacy)
        #expect(identity.authorizes(legacy))
        clock.generation.advance()
        #expect(identity.resolveID(group: home, defaultID: legacy) == legacy)
        #expect(identity.question == nil)

        harness.hint = .present(keyA)
        #expect(identity.resolveID(group: home, defaultID: legacy) == siteN)
    }

    /// "New network" with no hint makes a network holding the group's no-hint approval.
    @Test func aNewNetworkWithoutAHintHoldsTheNoHintApproval() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        harness.hint = .present(keyB)
        _ = identity.resolveID(group: home, defaultID: siteA)
        try identity.answer(.newNetwork, to: #require(identity.question))
        _ = identity.resolveID(group: home, defaultID: siteA)
        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: siteA)
        try identity.answer(.newNetwork, to: #require(identity.question))
        let approval = try #require(store.contents.approvals.first { $0.key == .noHint })
        #expect(approval.recordID != siteA)
        #expect(identity.resolveID(group: home, defaultID: siteA) == approval.recordID)
    }

    /// One record per group holds the no-hint approval: answering again moves it.
    @Test func aSecondNoHintAnswerMovesTheApproval() {
        let first = UUID()
        let second = UUID()
        var contents = NetworkIdentityStore.Contents(
            revision: 1,
            records: [IdentityRecord(id: first, group: home, recordClass: .bound), IdentityRecord(id: second, group: home, recordClass: .bound)],
            legacyIDs: []
        )
        NetworkIdentityController.approve(.noHint, group: home, on: first, now: Date(), in: &contents)
        NetworkIdentityController.approve(.noHint, group: home, on: second, now: Date(), in: &contents)
        #expect(contents.approvals.filter { $0.key == .noHint }.map(\.recordID) == [second])
    }

    /// A failed read never uses or creates the no-hint approval, and an answer clicked during one
    /// isn't lost: the question stays, with "Checking the network…".
    @Test func aFailedReadNeverUsesOrCreatesTheNoHintApproval() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.probeAnswer = false
        let identity = makeController(store, harness)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        try identity.answer(.newNetwork, to: #require(identity.question))
        let siteN = identity.resolveID(group: home, defaultID: legacy)
        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: siteN)
        let question = try #require(identity.question)

        harness.hint = .failed
        identity.answer(.thisConnection(legacy), to: question)
        #expect(!store.contents.approvals.contains { $0.key == .noHint })
        #expect(identity.question == question)
        #expect(identity.isCheckingNetwork)

        harness.hint = .absent
        identity.answer(.thisConnection(legacy), to: question)
        #expect(store.contents.approvals.contains(IdentityApproval(group: home, key: .noHint, recordID: legacy)))
        // Failed reads past the retries count as no hint, but never as the approval's settled absence.
        harness.hint = .failed
        for _ in 0 ... NetworkIdentityController.failedHintRetries {
            _ = identity.resolveID(group: home, defaultID: legacy)
        }
        let asked = try #require(identity.question)
        #expect(Set(NetworkIdentityController.options(of: asked)) == [siteN, legacy], "asked, not the approval")
    }

    /// A kept legacy question whose probe couldn't run (nil) is probed once more on the next detection.
    @Test func aLegacyQuestionFromAProbeThatCouldNotRunIsProbedOnceMore() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.probeAnswer = nil
        let identity = makeController(store, harness)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        #expect(identity.question != nil)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        #expect(harness.probes == 2)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        #expect(harness.probes == 2, "once")
    }

    /// A bucket whose saved devices can't be counted is a candidate: ask, don't assume it's empty.
    @Test func aBucketThatCannotBeCountedIsACandidate() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .absent
        let identity = makeController(store, harness)
        let bucket = identity.resolveID(group: home, defaultID: UUID())
        harness.hint = .present(keyA)
        let siteA = identity.resolveID(group: home, defaultID: bucket)
        #expect(siteA != bucket)
        identity.describeOption = { _ in IdentityOptionSummary(savedDevices: 0, countUnknown: true) }
        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: siteA)
        #expect(identity.question == .forgottenThisConnection(group: home, options: [siteA, bucket]))
    }

    /// Item 3's same-generation failed read keeps the network and reads again.
    @Test func aFailedReadWithinTheGenerationKeepsTheNetworkAndRetries() async throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        harness.hint = .failed
        #expect(identity.resolveID(group: home, defaultID: siteA) == siteA)
        #expect(identity.authorizes(siteA))
        #expect(try #require(await eventually { harness.detections >= 1 }))
    }
}

extension NetworkIdentityStoreTests {
    /// A forgotten network stays forgotten through Start over even when its ID is in the v1 map.
    @Test func startOverKeepsAForgottenV1NetworkForgotten() throws {
        let env = try makeEnvironment()
        let store = store(env)
        try store.update { contents in
            if let index = contents.records.firstIndex(where: { $0.id == legacyID }) {
                contents.records[index].recordClass = .forgotten
            }
            contents.legacyIDs.removeAll { $0 == legacyID }
        }
        try Data("not json".utf8).write(to: env.dir.appending(path: NetworkIdentityStore.fileName))
        let damaged = self.store(env)
        try damaged.startOver()
        #expect(damaged.contents.records.first { $0.id == legacyID }?.recordClass == .forgotten)
    }

    /// A newer build's file whose shape this build can't decode is still `.newer`: no quarantine,
    /// no tombstone, no Start over.
    @Test func aNewerFileThisBuildCannotDecodeIsNewer() throws {
        let env = try makeEnvironment()
        _ = store(env)
        let url = env.dir.appending(path: NetworkIdentityStore.fileName)
        try Data(#"{"schemaVersion": 99, "networks": {"a": 1}}"#.utf8).write(to: url)
        let newer = store(env)
        #expect(newer.state == .newer)
        #expect(!env.defaults.bool(forKey: NetworkIdentityStore.damagedKey))
        let copies = try FileManager.default.contentsOfDirectory(atPath: env.dir.path).filter { $0.contains(".damaged-") }
        #expect(copies.isEmpty)
        #expect(throws: (any Error).self) { try newer.startOver() }
    }
}
