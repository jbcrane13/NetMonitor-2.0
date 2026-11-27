import Foundation
import Testing
@testable import NetMonitorCore

/// #645 round 5: the no-hint settle window, moving and correcting the no-hint approval.
extension NetworkIdentityControllerTests {
    /// Home L (from before identification) holds the no-hint approval; N, made at an IPv6 site on
    /// the same subnet, is bound by its router.
    private func homeAndSite(_ harness: Harness, clock: NetworkJoinClock) async throws
        -> (NetworkIdentityController, NetworkIdentityStore, home: UUID, site: UUID) {
        let homeID = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": homeID])
        let identity = makeController(store, harness, clock: clock)
        harness.hint = .present(keyA)
        harness.probeAnswer = false
        _ = identity.resolveID(group: home, defaultID: homeID)
        await identity.probeTask?.value
        try identity.answer(.newNetwork, to: #require(identity.question))
        let site = identity.resolveID(group: home, defaultID: homeID)
        #expect(site != homeID)
        harness.hint = .absent
        clock.generation.advance()
        _ = identity.resolveID(group: home, defaultID: site)
        harness.settle()
        _ = identity.resolveID(group: home, defaultID: site)
        try identity.answer(.thisConnection(homeID), to: #require(identity.question))
        #expect(identity.resolveID(group: home, defaultID: site) == homeID)
        #expect(identity.authorizes(homeID))
        return (identity, store, homeID, site)
    }

    /// Joining N's site before its router advertisement arrives: absent at first, the hint at 2 s.
    /// The no-hint approval (home) is never used; it resolves by the hint.
    @Test func aLateRouterAdvertisementNeverSavesTheSiteIntoHome() async throws {
        let harness = Harness()
        let clock = NetworkJoinClock.forIdentityTests
        let (identity, _, homeID, site) = try await homeAndSite(harness, clock: clock)
        clock.generation.advance()
        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: homeID)
        #expect(!identity.authorizes(homeID), "inside the settle window")
        #expect(identity.heldNetworkIDs == [homeID])
        harness.now += 2
        harness.hint = .present(keyA)
        #expect(identity.resolveID(group: home, defaultID: homeID) == site)
        #expect(!identity.authorizes(homeID))
        #expect(identity.authorizes(site))
    }

    /// Absent throughout: home after the window, settled once, and a re-read is scheduled for its end.
    @Test func absentThroughoutTheWindowIsHome() async throws {
        let harness = Harness()
        let clock = NetworkJoinClock.forIdentityTests
        let (identity, _, homeID, _) = try await homeAndSite(harness, clock: clock)
        var settled = 0
        identity.onSettled = { _ in settled += 1 }
        clock.generation.advance()
        let detections = harness.detections
        _ = identity.resolveID(group: home, defaultID: homeID)
        #expect(!identity.authorizes(homeID))
        #expect(try #require(await eventually { harness.detections > detections }), "a re-read at the window's end")
        harness.settle()
        #expect(identity.resolveID(group: home, defaultID: homeID) == homeID)
        #expect(identity.authorizes(homeID))
        #expect(settled == 1)
    }

    /// A no-hint answer is accepted only once absent has settled.
    @Test func aNoHintAnswerInsideTheWindowIsNotAccepted() async throws {
        let homeID = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": homeID])
        let harness = Harness()
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        harness.hint = .present(keyA)
        harness.probeAnswer = false
        _ = identity.resolveID(group: home, defaultID: homeID)
        await identity.probeTask?.value
        try identity.answer(.newNetwork, to: #require(identity.question))
        let site = identity.resolveID(group: home, defaultID: homeID)
        harness.hint = .absent
        clock.generation.advance()
        _ = identity.resolveID(group: home, defaultID: site)
        harness.settle()
        _ = identity.resolveID(group: home, defaultID: site)
        let question = try #require(identity.question)
        // A path update: the kept question is answered inside the new generation's window.
        clock.generation.advance()
        _ = identity.resolveID(group: home, defaultID: site)
        identity.answer(.thisConnection(homeID), to: question)
        #expect(!store.contents.approvals.contains { $0.key == .noHint })
        #expect(identity.isCheckingNetwork)
        #expect(identity.question == question)
    }

    /// A router appearing later in the generation, after home was identified: held from then on.
    @Test func aRouterAppearingAfterHomeWasIdentifiedHolds() async throws {
        let harness = Harness()
        let clock = NetworkJoinClock.forIdentityTests
        let (identity, _, homeID, _) = try await homeAndSite(harness, clock: clock)
        harness.hint = .present(keyB)
        #expect(!identity.authorizes(homeID))
        #expect(identity.heldNetworkIDs == [homeID])
    }

    /// Moving the no-hint approval off a network bound only by it keeps the store valid: through
    /// "Not this network?" and a new answer.
    @Test func movingTheNoHintApprovalKeepsTheStoreValid() async throws {
        let harness = Harness()
        let clock = NetworkJoinClock.forIdentityTests
        let (identity, store, homeID, site) = try await homeAndSite(harness, clock: clock)
        #expect(identity.canReidentify)
        identity.reidentifyWithoutHint()
        #expect(!identity.saveFailed)
        #expect(!store.contents.approvals.contains { $0.key == .noHint })
        _ = identity.resolveID(group: home, defaultID: homeID)
        harness.settle()
        let question = try #require(identity.question)
        identity.answer(.thisConnection(site), to: question)
        #expect(!identity.saveFailed)
        #expect(store.contents.approvals.contains(IdentityApproval(group: home, key: .noHint, recordID: site)))
        #expect(identity.resolveID(group: home, defaultID: homeID) == site)
    }

    /// A kept question that survives a path update is still tentative in the new generation.
    @Test func aKeptQuestionStaysTentativeAcrossAPathUpdate() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.probeAnswer = false
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        #expect(identity.question != nil)
        clock.generation.advance()
        _ = identity.resolveID(group: home, defaultID: legacy)
        #expect(identity.wasOnlyTentative(legacy))
    }

    /// While reads keep failing, the open question stays, saying "Checking the network…".
    @Test func failingReadsKeepTheOpenQuestion() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.probeAnswer = false
        let identity = makeController(store, harness)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        let question = try #require(identity.question)
        harness.hint = .failed
        _ = identity.resolveID(group: home, defaultID: legacy)
        #expect(identity.question == question)
        #expect(identity.isCheckingNetwork)
    }
}
