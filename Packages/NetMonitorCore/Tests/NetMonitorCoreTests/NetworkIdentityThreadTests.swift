import Foundation
import Testing
@testable import NetMonitorCore

/// #645 review threads that were still live on 91fb40df.
extension NetworkIdentityControllerTests {
    /// A no-hint approval holds across a wake once absent has settled again (round 5: a wake starts a
    /// new settle window); a router appearing goes by its own key.
    @Test func aNoHintApprovalSurvivesAWakeButNotARouter() throws {
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
        harness.settle()
        try identity.answer(.thisConnection(siteA), to: #require(identity.question))
        #expect(identity.resolveID(group: home, defaultID: siteA) == siteA)
        clock.noteResume()
        #expect(!identity.authorizes(siteA), "inside the new generation's window")
        harness.settle()
        #expect(identity.resolveID(group: home, defaultID: siteA) == siteA)
        #expect(identity.authorizes(siteA))
        harness.hint = .present(keyB)
        #expect(!identity.authorizes(siteA))
    }

    /// Automatic approvals (a new network's own key, a quiet bind) go through the same cap as answers.
    @Test func automaticApprovalsKeepTheCap() throws {
        let (store, _, _) = try makeStore()
        try store.update { contents in
            for index in 0 ..< NetworkIdentityController.approvalsInAll {
                let group = NetworkGroup(interface: "en9", subnet: "10.\(index).0.0/24")
                let id = UUID()
                contents.records.append(IdentityRecord(id: id, group: group, recordClass: .bound))
                contents.approvals.append(IdentityApproval(group: group, key: RouterKey(["k\(index)"]), recordID: id))
            }
        }
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        _ = identity.resolveID(group: home, defaultID: UUID())
        #expect(store.contents.approvals.count == NetworkIdentityController.approvalsInAll)
    }
}

/// Installs from before the v1 map: the local profile saved then seeds its ID, as the profile
/// manager always did, so identification migrates it as a legacy network instead of letting another
/// router inherit its devices.
@Suite("Pre-v1 local profile")
@MainActor
struct PreV1LocalProfileTests {
    @Test func theSavedLocalProfileIsAKnownLocalNetwork() throws {
        let suite = "identity-prev1-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let live = NetworkProfile(
            interfaceName: "en0", ipAddress: "192.168.1.10",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A8_0100, broadcastAddress: 0xC0A8_01FF, interfaceAddress: 0xC0A8_010A, netmask: 0xFFFF_FF00
            ),
            connectionType: .wifi
        )
        let manager = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [live] })
        let saved = try #require(manager.localProfile?.id)
        // A build from before the map: only the profile list was saved.
        defaults.removeObject(forKey: "netmonitor.knownLocalNetworkIDs")
        #expect(NetworkProfileManager.knownLocalNetworkIDs(in: defaults) == ["en0|192.168.1.0/24": saved])
    }
}
