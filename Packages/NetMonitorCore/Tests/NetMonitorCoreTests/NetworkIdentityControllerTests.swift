import Foundation
import Testing
@testable import NetMonitorCore

/// #628 PR B: the Mac identifies which same-subnet network it is on before saving device rows.
@Suite("Network identity controller", .serialized)
@MainActor
struct NetworkIdentityControllerTests {
    let home = NetworkGroup(interface: "en0", subnet: "192.168.1.0/24")
    let keyA = RouterKey(["aaaa"])
    let keyB = RouterKey(["bbbb"])

    final class Harness {
        var hint: RouterHintStatus = .absent
        var detections = 0
        var probeAnswer: Bool? = true
        var probes = 0
        var probeGate: CheckedContinuation<Void, Never>?
        var holdsProbe = false
    }

    private func makeStore(
        legacy: [String: UUID] = [:], dir: URL? = nil, defaults: UserDefaults? = nil
    ) throws -> (NetworkIdentityStore, URL, UserDefaults) {
        let dir = dir ?? FileManager.default.temporaryDirectory.appending(path: "identity-\(UUID().uuidString)", directoryHint: .isDirectory)
        let defaults = try defaults ?? #require(UserDefaults(suiteName: "identity-\(UUID().uuidString)"))
        return (NetworkIdentityStore(directory: dir, defaults: defaults, legacyNetworks: { legacy }, reservedIDs: { [] }), dir, defaults)
    }

    private func makeController(
        _ store: NetworkIdentityStore, _ harness: Harness, clock: NetworkJoinClock = .forIdentityTests, launchID: UUID = UUID()
    ) -> NetworkIdentityController {
        NetworkIdentityController(
            store: store, clock: clock, launchID: launchID,
            readHint: { _ in harness.hint },
            probe: { _, _ in
                harness.probes += 1
                if harness.holdsProbe {
                    await withCheckedContinuation { harness.probeGate = $0 }
                }
                return harness.probeAnswer
            },
            requestDetection: { harness.detections += 1 }
        )
    }

    @Test func aNewRouterInAnEmptyGroupIsANewNetworkUnderTodaysID() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let today = UUID()
        #expect(identity.resolveID(group: home, defaultID: today) == today)
        #expect(identity.authorizes(today))
        #expect(identity.heldNetworkIDs.isEmpty)
        #expect(store.contents.approvals == [IdentityApproval(group: home, key: keyA, recordID: today)])
    }

    @Test func anApprovedRouterIsThatNetwork() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let home = identity.resolveID(group: self.home, defaultID: UUID())
        #expect(identity.resolveID(group: self.home, defaultID: UUID()) == home)
        #expect(identity.authorizes(home))
    }

    @Test func anUnapprovedRouterAsksAndHoldsTheKnownNetworksRows() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let siteA = identity.resolveID(group: home, defaultID: UUID())

        harness.hint = .present(keyB)
        #expect(identity.resolveID(group: home, defaultID: siteA) == siteA)
        #expect(identity.question == .whichNetwork(group: home, key: keyB, options: [siteA]))
        #expect(!identity.authorizes(siteA))
        #expect(identity.heldNetworkIDs == [siteA])
    }

    @Test func aNewNetworkAnswerPersistsAndActivatesOnlyAgainstAMatchingDetection() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        harness.hint = .present(keyB)
        _ = identity.resolveID(group: home, defaultID: siteA)
        let question = try #require(identity.question)

        identity.answer(.newNetwork, to: question)
        let approval = try #require(store.contents.approvals.first { $0.key == keyB })
        #expect(approval.recordID != siteA)
        #expect(harness.detections == 1)
        // Not active until a detection with the same group and key completes.
        #expect(!identity.authorizes(approval.recordID))
        #expect(identity.resolveID(group: home, defaultID: siteA) == approval.recordID)
        #expect(identity.authorizes(approval.recordID))
    }

    @Test func aStaleAnswerFromAnotherSiteStoresTheApprovalButDoesNotActivate() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        harness.hint = .present(keyB)
        _ = identity.resolveID(group: home, defaultID: siteA)
        let question = try #require(identity.question)

        // The Mac has moved on to a third router before the user answers about B.
        let keyC = RouterKey(["cccc"])
        harness.hint = .present(keyC)
        identity.answer(.same(siteA), to: question)
        #expect(store.contents.approvals.contains(IdentityApproval(group: home, key: keyB, recordID: siteA)))
        #expect(identity.resolveID(group: home, defaultID: siteA) == siteA)
        #expect(identity.question == .whichNetwork(group: home, key: keyC, options: [siteA]))
        #expect(!identity.authorizes(siteA))
    }

    /// The Mac moves to a same-subnet site with no path update: the router re-read at commit catches
    /// it, withdraws authorization and presentation at once, and asks for one detection.
    @Test func aCommitTimeRouterMismatchWithNoPathEventHoldsAndAsksForOneDetection() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        #expect(identity.authorizes(siteA))

        harness.hint = .present(keyB)
        #expect(!identity.authorizes(siteA))
        #expect(identity.heldNetworkIDs == [siteA])
        #expect(!identity.authorizes(siteA))
        #expect(harness.detections == 1, "coalesced")
    }

    @Test func aLegacyNetworkWithAClearOverlapIsBoundQuietly() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        #expect(identity.resolveID(group: home, defaultID: legacy) == legacy)
        #expect(!identity.authorizes(legacy), "identifying while the probe runs")
        #expect(identity.heldNetworkIDs == [legacy])
        await identity.probeTask?.value
        #expect(identity.authorizes(legacy))
        #expect(store.contents.approvals == [IdentityApproval(group: home, key: keyA, recordID: legacy)])
        #expect(harness.probes == 1)
    }

    @Test func aLegacyNetworkWithoutAClearOverlapAsks() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.probeAnswer = false
        let identity = makeController(store, harness)
        _ = identity.resolveID(group: home, defaultID: legacy)
        await identity.probeTask?.value
        #expect(identity.question == .isLegacy(group: home, key: keyA, record: legacy))
        #expect(!identity.authorizes(legacy))
        #expect(store.contents.approvals.isEmpty)
    }

    @Test func aProbeAPathUpdateOverranIsDiscarded() async throws {
        let legacy = UUID()
        let (store, _, _) = try makeStore(legacy: ["en0|192.168.1.0/24": legacy])
        let harness = Harness()
        harness.hint = .present(keyA)
        harness.holdsProbe = true
        let clock = NetworkJoinClock.forIdentityTests
        let identity = makeController(store, harness, clock: clock)
        _ = identity.resolveID(group: home, defaultID: legacy)
        while harness.probeGate == nil {
            await Task.yield()
        }
        clock.generation.advance()
        harness.probeGate?.resume()
        await identity.probeTask?.value
        #expect(store.contents.approvals.isEmpty)
        #expect(!identity.authorizes(legacy))
    }

    @Test func aConnectionOnlyAnswerHoldsForItsLaunchAndGenerationOnly() throws {
        let (store, dir, defaults) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let clock = NetworkJoinClock.forIdentityTests
        let launch = UUID()
        let identity = makeController(store, harness, clock: clock, launchID: launch)
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
        #expect(question == .forgottenThisConnection(group: home, options: [siteA]))

        identity.answer(.thisConnection(siteA), to: question)
        #expect(identity.resolveID(group: home, defaultID: siteA) == siteA)
        #expect(identity.authorizes(siteA))

        // Another launch, same generation number: asked again.
        let reopened = NetworkIdentityStore(directory: dir, defaults: defaults, legacyNetworks: { [:] }, reservedIDs: { [] })
        let relaunched = makeController(reopened, harness, clock: clock)
        _ = relaunched.resolveID(group: home, defaultID: siteA)
        #expect(relaunched.question == question)
        // The same launch after a path update: asked again.
        clock.generation.advance()
        _ = identity.resolveID(group: home, defaultID: siteA)
        #expect(identity.question == question)
    }

    @Test func settlingAfterAHoldTellsTheOwnerOnceAndALaunchIdentificationDoesNot() throws {
        let (store, _, _) = try makeStore()
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(store, harness)
        var settled: [UUID] = []
        identity.onSettled = { settled.append($0) }
        let siteA = identity.resolveID(group: home, defaultID: UUID())
        #expect(settled.isEmpty, "the launch scan already runs under it")
        harness.hint = .present(keyB)
        _ = identity.resolveID(group: home, defaultID: siteA)
        let question = try #require(identity.question)
        identity.answer(.same(siteA), to: question)
        _ = identity.resolveID(group: home, defaultID: siteA)
        _ = identity.resolveID(group: home, defaultID: siteA)
        #expect(settled == [siteA])
    }

    @Test func startOverClearsTheDamageAndDetectsAgain() throws {
        let (_, dir, defaults) = try makeStore()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appending(path: NetworkIdentityStore.fileName))
        let damaged = NetworkIdentityStore(directory: dir, defaults: defaults, legacyNetworks: { [:] }, reservedIDs: { [] })
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(damaged, harness)
        let id = identity.resolveID(group: home, defaultID: UUID())
        #expect(identity.isDamaged)
        identity.startOver()
        #expect(!identity.isDamaged)
        #expect(harness.detections == 1)
        #expect(identity.resolveID(group: home, defaultID: id) == id)
        #expect(identity.authorizes(id))
    }

    @Test func aDamagedStoreHoldsEverything() throws {
        let (store, dir, defaults) = try makeStore()
        try Data("not json".utf8).write(to: dir.appending(path: NetworkIdentityStore.fileName))
        let damaged = NetworkIdentityStore(directory: dir, defaults: defaults, legacyNetworks: { [:] }, reservedIDs: { [] })
        _ = store
        let harness = Harness()
        harness.hint = .present(keyA)
        let identity = makeController(damaged, harness)
        let id = UUID()
        #expect(identity.resolveID(group: home, defaultID: id) == id)
        #expect(identity.isDamaged)
        #expect(!identity.authorizes(id))
        #expect(identity.heldNetworkIDs == [id])
    }
}

@MainActor
extension NetworkJoinClock {
    /// A clock of the test's own; the network check is the controller's business, not the clock's.
    static var forIdentityTests: NetworkJoinClock {
        let clock = NetworkJoinClock(changes: AsyncStream<String>.makeStream().stream)
        clock.networkIsCurrent = { _ in true }
        return clock
    }
}

/// #628 PR B: the Mac's profile manager takes the local network's ID from identification.
@Suite("Profile manager identity hook")
@MainActor
struct ProfileManagerIdentityHookTests {
    @Test func theDetectedLocalNetworkTakesTheIdentitysID() throws {
        let defaults = try #require(UserDefaults(suiteName: "identity-hook-\(UUID().uuidString)"))
        let live = NetworkProfile(
            interfaceName: "en0", ipAddress: "192.168.1.10",
            network: NetworkUtilities.IPv4Network(networkAddress: 0xC0A8_0100, broadcastAddress: 0xC0A8_01FF, interfaceAddress: 0xC0A8_010A, netmask: 0xFFFF_FF00),
            connectionType: .wifi
        )
        let manager = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [live] })
        let legacy = try #require(manager.localProfile?.id)
        #expect(NetworkProfileManager.knownLocalNetworkIDs(in: defaults) == ["en0|192.168.1.0/24": legacy])

        let identified = UUID()
        var asked: [NetworkGroup] = []
        manager.localNetworkIdentity = { group, defaultID in
            asked.append(group)
            #expect(defaultID == legacy)
            return identified
        }
        manager.detectLocalNetwork()
        #expect(asked == [NetworkGroup(interface: "en0", subnet: "192.168.1.0/24")])
        #expect(manager.localProfile?.id == identified)
        #expect(NetworkProfileManager.savedLocalProfile(in: defaults)?.id == identified)
    }
}
