import Foundation
import Testing
@testable import NetMonitorCore

/// #645 review part 2: a lost or unreadable IPv6 hint, option names, the Ask guard, Start over and
/// approval eviction.
extension NetworkIdentityControllerTests {
    /// An IPv6 drop (an ISP outage, a late router advertisement after wake): the one bound network
    /// keeps its ID and its rows.
    @Test func aBoundNetworkKeepsItsIDWhenTheHintGoesAbsent() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: siteA)
        harness.settle()
        #expect(identity.resolveID(group: home, defaultID: siteA) == siteA)
        #expect(identity.authorizes(siteA))
        #expect(!store.contents.records.contains { $0.recordClass == .bucket })
    }

    /// An unreadable routing table is transient: the current authorization stays, and nothing is bucketed.
    @Test func aFailedHintKeepsTheCurrentNetwork() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        harness.hint = .failed
        #expect(identity.authorizes(siteA))
        #expect(identity.resolveID(group: home, defaultID: siteA) == siteA)
        #expect(identity.authorizes(siteA))
        #expect(!store.contents.records.contains { $0.recordClass == .bucket })
    }

    /// With nothing identified yet, a failed read holds and detects again a few times before it
    /// counts as no hint.
    @Test func aFailedHintWithNothingIdentifiedRetriesBeforeBucketing() async throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .failed
        let identity = makeController(store, harness)
        let today = UUID()
        #expect(identity.resolveID(group: home, defaultID: today) == today)
        #expect(!identity.authorizes(today))
        #expect(!store.contents.records.contains { $0.recordClass == .bucket })
        #expect(try #require(await eventually { harness.detections == 1 }))
        for _ in 1 ..< NetworkIdentityController.failedHintRetries {
            _ = identity.resolveID(group: home, defaultID: today)
        }
        _ = identity.resolveID(group: home, defaultID: today)
        #expect(store.contents.records.contains { $0.recordClass == .bucket })
    }

    /// Two bound sites and no hint: one question, its options named by what they hold.
    @Test func twoBoundSitesWithoutAHintAskOnceWithEachOptionDescribed() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        harness.hint = .present(keyB)
        _ = identity.resolveID(group: home, defaultID: siteA)
        try identity.answer(.newNetwork, to: #require(identity.question))
        let siteB = identity.resolveID(group: home, defaultID: siteA)
        #expect(siteB != siteA)

        identity.describeOption = { id in
            IdentityOptionSummary(savedDevices: id == siteA ? 12 : 3, lastScanned: nil, name: nil)
        }
        harness.hint = .absent
        _ = identity.resolveID(group: home, defaultID: siteB)
        harness.settle()
        _ = identity.resolveID(group: home, defaultID: siteB)
        #expect(identity.question == .forgottenThisConnection(group: home, options: [siteA, siteB]))
        #expect(identity.optionSummaries[siteA]?.savedDevices == 12)
        #expect(identity.optionSummaries[siteB]?.savedDevices == 3)
        // What an option holds can change while the question is open: the card refreshes it.
        identity.describeOption = { _ in IdentityOptionSummary(savedDevices: 5) }
        identity.refreshOptionSummaries()
        #expect(identity.optionSummaries[siteA]?.savedDevices == 5)
        #expect(!identity.authorizes(siteA))
        #expect(!identity.authorizes(siteB))
    }

    /// #627's Ask guard: a hold withdraws the network's "established" scan, so Ask doesn't ping as if
    /// on the old network.
    @Test func aRouterMismatchClearsTheEstablishedScan() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        clock.scanReconciled(clock.token(for: nil), at: Date())
        #expect(clock.establishedAt != nil)
        harness.hint = .present(keyB)
        #expect(!identity.authorizes(siteA))
        #expect(clock.establishedAt == nil)
    }

    /// Two copies answer the same question: the stale one's write conflicts, and Try again re-resolves
    /// against what the other saved instead of replaying the answer over it.
    @Test func aConflictingAnswerReResolvesInsteadOfReplaying() throws {
        let (store, dir, defaults) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let first = makeController(store, harness)
        let siteA = first.resolveID(group: home, defaultID: UUID())
        let otherStore = NetworkIdentityStore(directory: dir, defaults: defaults, legacyNetworks: { [:] }, reservedIDs: { [] })
        let otherHarness = Harness()
        otherHarness.hint = .present(keyB)
        let other = makeController(otherStore, otherHarness)
        harness.hint = .present(keyB)
        _ = first.resolveID(group: home, defaultID: siteA)
        _ = other.resolveID(group: home, defaultID: siteA)
        let question = try #require(first.question)
        #expect(other.question == question)

        first.answer(.newNetwork, to: question)
        let firstsChoice = try #require(store.contents.approvals.first { $0.key == keyB }?.recordID)
        other.answer(.same(siteA), to: question)
        #expect(other.saveFailed)
        other.retrySave()
        #expect(otherHarness.detections == 1, "re-resolves")
        #expect(otherStore.contents.approvals.first { $0.key == keyB }?.recordID == firstsChoice, "the other copy's answer stands")
        #expect(other.resolveID(group: home, defaultID: siteA) == firstsChoice)
    }

    /// Eviction takes the least recently matched approval, not the oldest.
    @Test func evictionTakesTheLeastRecentlyMatchedApproval() {
        let site = UUID()
        var contents = NetworkIdentityStore.Contents(
            revision: 1, records: [IdentityRecord(id: site, group: home, recordClass: .bound)], legacyIDs: []
        )
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0 ..< NetworkIdentityController.approvalsPerNetwork {
            // The first added is the most recently matched.
            let matched = base.addingTimeInterval(index == 0 ? 10000 : Double(index))
            contents.approvals.append(IdentityApproval(group: home, key: RouterKey(["k\(index)"]), recordID: site, lastMatched: matched))
        }
        NetworkIdentityController.approve(RouterKey(["new"]), group: home, on: site, now: base.addingTimeInterval(20000), in: &contents)
        let keys = Set(contents.approvals.map(\.key))
        #expect(keys.contains(RouterKey(["k0"])))
        #expect(!keys.contains(RouterKey(["k1"])))
        #expect(keys.contains(RouterKey(["new"])))
    }
}

extension NetworkIdentityStoreTests {
    /// "Starting over keeps your devices": a network split off by an answer is offered again after a
    /// start over, not only the networks from before identification.
    @Test func startOverKeepsSplitOffNetworks() throws {
        let env = try makeEnvironment()
        let store = store(env)
        let split = UUID()
        let group = NetworkGroup(interface: "en0", subnet: "192.168.1.0/24")
        try store.update { contents in
            contents.records.append(IdentityRecord(id: split, group: group, recordClass: .bound))
            contents.approvals.append(IdentityApproval(group: group, key: RouterKey(["b"]), recordID: split))
        }
        try Data("not json".utf8).write(to: env.dir.appending(path: NetworkIdentityStore.fileName))
        let damaged = self.store(env)
        #expect(damaged.state == .damaged)
        try damaged.startOver()
        #expect(damaged.contents.records.contains { $0.id == split && $0.recordClass == .legacyUnverified && $0.group == group })
        #expect(damaged.contents.records.contains { $0.id == legacyID })
        #expect(damaged.contents.revision > 2, "the revision continues, so a stale copy can't pass the check")
    }

    /// A name the user gave a network, never the generated one that every site on a subnet shares.
    @Test func onlyAUserGivenNameIsACustomName() {
        let network = NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A8_0100, broadcastAddress: 0xC0A8_01FF, interfaceAddress: 0xC0A8_010A, netmask: 0xFFFF_FF00
        )
        let generated = NetworkProfile(interfaceName: "en0", ipAddress: "192.168.1.10", network: network, connectionType: .wifi)
        #expect(generated.customName == nil)
        let named = NetworkProfile(
            interfaceName: "en0", ipAddress: "192.168.1.10", network: network, connectionType: .wifi, displayName: "Home office"
        )
        #expect(named.customName == "Home office")
    }
}

/// #645: Ask reads a held network through the held snapshot, which has no last scan, so it never
/// cites a held row as online.
@Suite("Ask on a held network")
struct AskHeldNetworkTests {
    @Test func aHeldNetworksOnlineRowIsNotCitedAsOnline() {
        let network = UUID()
        let now = Date(timeIntervalSince1970: 2_000_000)
        let held = PresenceSnapshot(lastScans: [network: now], now: now).withHeld([network])
        let device = AskDevice(
            id: UUID(), displayName: "office-printer", deviceType: .printer, maker: nil, ipAddress: "192.168.1.20",
            status: .online, lastSeen: now, lastLatency: 4, latencyHistory: []
        )
        let snapshot = AskSnapshot(
            devices: [device], events: [], networkProfileID: network, lastScan: held.lastScan(for: network), now: now
        )
        #expect(snapshot.presence(of: device) != .online)
        #expect(snapshot.freshnessNote.contains("no device's status has been checked"))
    }
}
