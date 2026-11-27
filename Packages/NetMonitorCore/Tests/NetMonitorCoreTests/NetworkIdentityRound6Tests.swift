import Foundation
import Testing
@testable import NetMonitorCore

/// #645 round 6: the settle window for every no-hint identification in a group that knows an IPv6
/// site, moving and releasing the no-hint approval, and a deferred answer.
extension NetworkIdentityControllerTests {
    /// Item 1: home L is bound by its router. Joining a new IPv6 site before its router
    /// advertisement: absent first, the hint at 2 s. L is never used.
    @Test func aBoundHomeIsNotUsedBeforeTheWindowSettles() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        let homeL = identity.resolveID(group: home, defaultID: UUID())
        clock.generation.advance()
        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: homeL)
        #expect(!identity.authorizes(homeL))
        harness.now += 2
        harness.hint = .present(keyB)
        _ = identity.resolveID(group: home, defaultID: homeL)
        #expect(!identity.authorizes(homeL))
        #expect(identity.question == .whichNetwork(group: home, key: keyB, options: [homeL]))
    }

    /// Item 1: an IPv4-only upgrader (a legacy network, no IPv6 site known) is identified at once.
    @Test func anIPv4OnlyLegacyNetworkIsIdentifiedAtOnce() throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .absent
        let identity = makeController(store, harness)
        #expect(identity.resolveID(group: home, defaultID: legacy) == legacy)
        #expect(identity.authorizes(legacy))
        #expect(identity.question == nil)
    }

    /// Items 2 and 3: the no-hint approval moves (a question asked while it exists, after failed
    /// reads ran out). The network left with nothing is removed if it holds nothing, and kept as
    /// legacy if the user named it.
    @Test(arguments: [false, true])
    func movingTheNoHintApprovalReleasesThePreviousNetwork(named: Bool) async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.summaries = [legacy: IdentityOptionSummary(savedDevices: 0, name: named ? "Home office" : nil)]
        harness.hint = .present(keyA)
        harness.probeAnswer = false
        let identity = makeController(store, harness)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        try identity.answer(.newNetwork, to: #require(identity.question))
        let siteN = identity.resolveID(group: home, defaultID: legacy)
        harness.summaries?[siteN] = IdentityOptionSummary(savedDevices: 4)
        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: siteN)
        harness.settle()
        _ = identity.resolveID(group: home, defaultID: siteN)
        try identity.answer(.thisConnection(legacy), to: #require(identity.question))
        #expect(store.contents.approvals.contains(IdentityApproval(group: home, key: .noHint, recordID: legacy)))
        // Reads fail past their retries: a question while the approval exists.
        harness.hint = .failed
        for _ in 0 ... NetworkIdentityController.failedHintRetries {
            _ = identity.resolveID(group: home, defaultID: legacy)
        }
        let question = try #require(identity.question)
        harness.hint = .absent
        identity.answer(.thisConnection(siteN), to: question)
        harness.settle()
        _ = identity.resolveID(group: home, defaultID: legacy)
        #expect(!identity.saveFailed)
        #expect(store.contents.approvals.contains(IdentityApproval(group: home, key: .noHint, recordID: siteN)))
        let left = store.contents.records.first { $0.id == legacy }
        if named {
            #expect(left?.recordClass == .legacyUnverified)
        } else {
            #expect(left == nil)
        }
    }

    /// Item 4: after "Not this network?", the cleared network is offered, never quietly re-bound.
    @Test func notThisNetworkAlwaysAsks() throws {
        let (store, _, _) = try makeStore()
        let homeL = UUID()
        try store.update { contents in
            contents.records.append(IdentityRecord(id: homeL, group: home, recordClass: .bound))
            contents.approvals.append(IdentityApproval(group: home, key: .noHint, recordID: homeL))
        }
        let harness = Harness()
        harness.summaries = [homeL: IdentityOptionSummary(savedDevices: 3)]
        harness.hint = .absent
        let identity = makeController(store, harness)
        _ = identity.resolveID(group: home, defaultID: homeL)
        harness.settle()
        #expect(identity.resolveID(group: home, defaultID: homeL) == homeL)
        identity.reidentifyWithoutHint()
        _ = identity.resolveID(group: home, defaultID: homeL)
        #expect(identity.question == .forgottenThisConnection(group: home, options: [homeL]))
        #expect(!identity.authorizes(homeL))
    }

    /// Item 5: an answer clicked inside the window is applied at its end if the hint still reads absent.
    @Test func anAnswerInsideTheWindowIsAppliedWhenItEnds() async throws {
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
        clock.generation.advance()
        _ = identity.resolveID(group: home, defaultID: siteN)
        harness.settle()
        _ = identity.resolveID(group: home, defaultID: siteN)
        let question = try #require(identity.question)
        clock.generation.advance()
        _ = identity.resolveID(group: home, defaultID: siteN)
        identity.answer(.thisConnection(legacy), to: question)
        #expect(!store.contents.approvals.contains { $0.key == .noHint })
        harness.settle()
        #expect(identity.resolveID(group: home, defaultID: siteN) == legacy)
        #expect(store.contents.approvals.contains(IdentityApproval(group: home, key: .noHint, recordID: legacy)))
    }
}
