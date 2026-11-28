import Foundation
import Testing
@testable import NetMonitorCore

/// #645 round 8: the disk-freshness check fails closed.
extension NetworkIdentityControllerTests {
    struct Fixture {
        let identity: NetworkIdentityController
        let other: NetworkIdentityStore
        let homeL: UUID
        let siteN: UUID
        let file: URL
    }

    /// L holds keyA; N exists: a controller about to be identified as L, and a second copy of the store.
    private func identifiedAsL(_ harness: Harness) throws -> Fixture {
        let (store, dir, defaults) = try makeStore()
        let homeL = UUID()
        let siteN = UUID()
        try store.update { contents in
            contents.records += [
                IdentityRecord(id: homeL, group: home, recordClass: .bound), IdentityRecord(id: siteN, group: home, recordClass: .bound)
            ]
            contents.approvals += [
                IdentityApproval(group: home, key: keyA, recordID: homeL), IdentityApproval(group: home, key: keyB, recordID: siteN)
            ]
        }
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let other = NetworkIdentityStore(directory: dir, defaults: defaults, legacyNetworks: { [:] }, reservedIDs: { [] })
        return Fixture(identity: identity, other: other, homeL: homeL, siteN: siteN, file: dir.appending(path: NetworkIdentityStore.fileName))
    }

    /// Item 1: the file can't be read after another copy moved the approval: no commit under L, and a
    /// second unreadable check moves to the damaged state with its recovery card.
    @Test func anUnreadableFileHoldsThenDamages() throws {
        let harness = Harness()
        let setup = try identifiedAsL(harness)
        #expect(setup.identity.resolveID(group: home, defaultID: setup.homeL) == setup.homeL)
        let move: (inout NetworkIdentityStore.Contents) -> Void = { contents in
            NetworkIdentityController.approve(self.keyA, group: self.home, on: setup.siteN, now: Date(), in: &contents)
        }
        // The second copy is stale (this copy stamped the match): a conflict reloads it, then it writes.
        do { try setup.other.update(move) } catch is NetworkIdentityStore.Conflict { try setup.other.update(move) }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: setup.file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: setup.file.path) }
        #expect(!setup.identity.authorizes(setup.homeL))
        #expect(!setup.identity.isDamaged, "one retry first")
        _ = setup.identity.resolveID(group: home, defaultID: setup.homeL)
        #expect(!setup.identity.authorizes(setup.homeL))
        #expect(setup.identity.isDamaged)
    }

    /// Item 2: two consecutive match-stamp conflicts, the second moving keyA from L to N: held, then N
    /// on the next detection; L is never authorized.
    @Test func twoMatchStampConflictsHoldThenResolveToTheNewNetwork() throws {
        let harness = Harness()
        let setup = try identifiedAsL(harness)
        harness.onRead = [
            { try setup.other.update { $0.records.append(IdentityRecord(id: UUID(), group: self.home, recordClass: .bucket)) } },
            {
                try setup.other.update { contents in
                    NetworkIdentityController.approve(self.keyA, group: self.home, on: setup.siteN, now: Date(), in: &contents)
                }
            }
        ]
        _ = setup.identity.resolveID(group: home, defaultID: setup.homeL)
        #expect(!setup.identity.authorizes(setup.homeL))
        #expect(setup.identity.resolveID(group: home, defaultID: setup.homeL) == setup.siteN)
        #expect(setup.identity.authorizes(setup.siteN))
        #expect(!setup.identity.authorizes(setup.homeL))
    }

    /// Item 3: another revision whose contents are invalid (missing arrays): the damaged state with
    /// its recovery, not a silent loop of re-identification.
    @Test func aChangedRevisionWithInvalidContentsIsDamaged() throws {
        let harness = Harness()
        let setup = try identifiedAsL(harness)
        #expect(setup.identity.resolveID(group: home, defaultID: setup.homeL) == setup.homeL)
        try Data(#"{"schemaVersion": 1, "revision": 999}"#.utf8).write(to: setup.file)
        #expect(!setup.identity.authorizes(setup.homeL))
        #expect(setup.identity.isDamaged)
    }
}
