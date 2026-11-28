import Foundation
import Testing
@testable import NetMonitorCore

/// #645 round 7 (Codex re-check of 5a535188).
extension NetworkIdentityControllerTests {
    /// Item 1: reads fail past their retries on A; the Mac moves to same-subnet B (a new generation)
    /// while they keep failing. B is held: nothing is identified or authorized as A.
    @Test func exhaustedFailedReadsDoNotCarryAcrossGenerations() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        harness.hint = .failed
        for _ in 0 ... NetworkIdentityController.failedHintRetries {
            _ = identity.resolveID(group: home, defaultID: siteA)
        }
        clock.generation.advance()
        for _ in 0 ... NetworkIdentityController.failedHintRetries + 1 {
            _ = identity.resolveID(group: home, defaultID: siteA)
            #expect(!identity.authorizes(siteA))
        }
        harness.settle()
        _ = identity.resolveID(group: home, defaultID: siteA)
        #expect(!identity.authorizes(siteA), "a converted failure never authorizes by itself")
    }

    /// Item 1: a network identified with no hint isn't kept on a failed read.
    @Test func aFailedReadDoesNotKeepANoHintIdentification() throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .absent
        let identity = makeController(store, harness)
        #expect(identity.resolveID(group: home, defaultID: legacy) == legacy)
        harness.hint = .failed
        #expect(!identity.authorizes(legacy))
    }

    /// Item 2: another copy moves the no-hint approval from L to N; this copy, identified as L, must
    /// re-resolve before saving anything.
    @Test func anotherCopyMovingTheNoHintApprovalIsSeenBeforeACommit() throws {
        let (store, dir, defaults) = try makeStore()
        let homeL = UUID()
        let siteN = UUID()
        try store.update { contents in
            contents.records += [
                IdentityRecord(id: homeL, group: home, recordClass: .bound), IdentityRecord(id: siteN, group: home, recordClass: .bound)
            ]
            contents.approvals += [
                IdentityApproval(group: home, key: .noHint, recordID: homeL), IdentityApproval(group: home, key: keyB, recordID: siteN)
            ]
        }
        let harness = Harness()
        harness.hint = .absent
        let identity = makeController(store, harness)
        _ = identity.resolveID(group: home, defaultID: homeL)
        harness.settle()
        #expect(identity.resolveID(group: home, defaultID: homeL) == homeL)

        let other = NetworkIdentityStore(directory: dir, defaults: defaults, legacyNetworks: { [:] }, reservedIDs: { [] })
        try other.update { contents in
            NetworkIdentityController.approve(.noHint, group: home, on: siteN, now: Date(), in: &contents)
        }
        #expect(!identity.authorizes(homeL), "the file moved: no commit under L")
        #expect(identity.resolveID(group: home, defaultID: homeL) == siteN)
        #expect(identity.authorizes(siteN))
    }
}

extension NetworkIdentityStoreTests {
    /// Item 3: Start over refuses a newer build's file written since this copy read it.
    @Test func startOverRefusesANewerFileWrittenMeanwhile() throws {
        let env = try makeEnvironment()
        _ = store(env)
        let url = env.dir.appending(path: NetworkIdentityStore.fileName)
        try Data("not json".utf8).write(to: url)
        let damaged = store(env)
        let newer = Data(#"{"schemaVersion": 99}"#.utf8)
        try newer.write(to: url)
        #expect(throws: (any Error).self) { try damaged.startOver() }
        #expect(damaged.state == .newer)
        #expect(try Data(contentsOf: url) == newer)
    }

    /// Item 3: Start over loads a valid file another copy repaired, instead of rebuilding over it.
    @Test func startOverLoadsAFileAnotherCopyRepaired() throws {
        let env = try makeEnvironment()
        _ = store(env)
        let url = env.dir.appending(path: NetworkIdentityStore.fileName)
        try Data("not json".utf8).write(to: url)
        let first = store(env)
        let second = store(env)
        try second.startOver()
        let added = UUID()
        try second.update { $0.records.append(IdentityRecord(id: added, group: home, recordClass: .bucket)) }
        try first.startOver()
        #expect(first.state == .ready)
        #expect(first.contents.records.contains { $0.id == added })
        #expect(first.contents.revision == second.contents.revision)
    }
}
