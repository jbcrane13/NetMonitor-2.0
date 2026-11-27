import Foundation
import Testing
@testable import NetMonitorCore

/// #628 PR B: which same-subnet network the Mac is on, by the IPv6 default router's link-local.
@Suite("Router hint")
struct RouterHintTests {
    /// fe80::2a70:4eff:fe84:d170 (EUI-64), scope bytes 0x0007 embedded as the kernel reports them.
    static let eui64: [UInt8] = [0xFE, 0x80, 0x00, 0x07, 0, 0, 0, 0, 0x2A, 0x70, 0x4E, 0xFF, 0xFE, 0x84, 0xD1, 0x70]

    @Test func anEUI64RouterIsIdentifyingAndTheScopeDoesNotChangeItsDigest() throws {
        var otherScope = Self.eui64
        otherScope[3] = 0x11
        let digest = try #require(RouterHint.digest(Self.eui64))
        #expect(RouterHint.digest(otherScope) == digest)
        #expect(digest.count == 64)
    }

    @Test func aLowEntropyRouterIsNotIdentifying() {
        let fe80one: [UInt8] = [0xFE, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
        let threeBytes: [UInt8] = [0xFE, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0A, 0x0B, 0x0C]
        #expect(RouterHint.digest(fe80one) == nil)
        #expect(RouterHint.digest(threeBytes) == nil)
    }

    @Test func aRandomInterfaceIDWithFourNonZeroBytesIsIdentifying() {
        let random: [UInt8] = [0xFE, 0x80, 0, 0, 0, 0, 0, 0, 0x91, 0, 0x3C, 0, 0x5D, 0, 0x7E, 0]
        #expect(RouterHint.digest(random) != nil)
    }

    @Test func aKeyIsTheSortedSetOfDigests() {
        #expect(RouterKey(["b", "a", "b"]) == RouterKey(["a", "b"]))
        #expect(RouterKey(["a"]) != RouterKey(["a", "b"]))
    }
}

@Suite("Network identity resolver")
struct NetworkIdentityResolverTests {
    let home = NetworkGroup(interface: "en0", subnet: "192.168.1.0/24")
    let other = NetworkGroup(interface: "en0", subnet: "10.0.0.0/24")
    let keyA = RouterKey(["aaaa"])
    let keyB = RouterKey(["bbbb"])

    private func record(_ cls: IdentityRecordClass, group: NetworkGroup? = nil) -> IdentityRecord {
        IdentityRecord(id: UUID(), group: group ?? home, recordClass: cls)
    }

    private func resolve(
        _ hint: RouterHintStatus, _ records: [IdentityRecord], approvals: [IdentityApproval] = [], connectionAnswer: UUID? = nil
    ) -> IdentityResolution {
        NetworkIdentityResolver.resolve(group: home, hint: hint, records: records, approvals: approvals, connectionAnswer: connectionAnswer)
    }

    // MARK: Step 2: no hint

    @Test func withoutAHintAForgottenRecordAsks() {
        let forgotten = record(.forgotten)
        let bucket = record(.bucket)
        #expect(resolve(.absent, [forgotten, bucket]) == .ask(.forgottenThisConnection(group: home, options: [forgotten.id])))
        #expect(resolve(.failed, [forgotten]) == .ask(.forgottenThisConnection(group: home, options: [forgotten.id])))
    }

    @Test func aConnectionOnlyAnswerIsUsedForItsConnection() {
        let forgotten = record(.forgotten)
        #expect(resolve(.absent, [forgotten], connectionAnswer: forgotten.id) == .use(forgotten.id))
    }

    @Test func withoutAHintTheLegacyRecordIsUsedWhenNothingIsBound() {
        let legacy = record(.legacyUnverified)
        #expect(resolve(.absent, [legacy]) == .use(legacy.id))
    }

    /// #645 (lead decision): an IPv6 drop never empties a bound network. One bound network without a
    /// hint is that network; several ask, for this connection only; the bucket is for a group with
    /// nothing bound.
    @Test func withoutAHintTheOneBoundNetworkIsUsed() {
        let bound = record(.bound)
        let legacy = record(.legacyUnverified)
        let bucket = record(.bucket)
        #expect(resolve(.absent, [bound, legacy, bucket]) == .use(bound.id))
        #expect(resolve(.absent, [bound]) == .use(bound.id))
    }

    @Test func withoutAHintSeveralBoundNetworksAskForThisConnection() {
        let siteA = record(.bound)
        let siteB = record(.bound)
        let forgotten = record(.forgotten)
        #expect(resolve(.absent, [siteA, siteB]) == .ask(.forgottenThisConnection(group: home, options: [siteA.id, siteB.id])))
        #expect(resolve(.absent, [siteA, forgotten]) == .ask(.forgottenThisConnection(group: home, options: [siteA.id, forgotten.id])))
    }

    @Test func withoutAHintTheBucketIsOnlyForAGroupWithNothingBound() {
        let bucket = record(.bucket)
        #expect(resolve(.absent, [bucket]) == .bucket(bucket.id))
        #expect(resolve(.absent, [record(.bound, group: other)]) == .bucket(nil))
        #expect(resolve(.absent, []) == .bucket(nil))
    }

    // MARK: Step 3: a hint

    @Test func anExactApprovalInThisGroupIsUsed() {
        let bound = record(.bound)
        let approvals = [IdentityApproval(group: home, key: keyA, recordID: bound.id)]
        #expect(resolve(.present(keyA), [bound], approvals: approvals) == .use(bound.id))
    }

    @Test func anApprovalForASubsetOfTheRoutersDoesNotAuthorizeTheSet() {
        let bound = record(.bound)
        let approvals = [IdentityApproval(group: home, key: keyA, recordID: bound.id)]
        let both = RouterKey(["aaaa", "bbbb"])
        #expect(resolve(.present(both), [bound], approvals: approvals) == .ask(.whichNetwork(group: home, key: both, options: [bound.id])))
    }

    @Test func theSameKeyInAnotherGroupIsOrdinaryUnmatchedEvidence() {
        let elsewhere = record(.bound, group: other)
        let approvals = [IdentityApproval(group: other, key: keyA, recordID: elsewhere.id)]
        #expect(resolve(.present(keyA), [], approvals: approvals) == .create(keyA))
    }

    @Test func anApprovalPointingAtAMissingOrUnboundRecordIsDamage() {
        let legacy = record(.legacyUnverified)
        #expect(resolve(.present(keyA), [], approvals: [IdentityApproval(group: home, key: keyA, recordID: UUID())]) == .damaged)
        #expect(resolve(.present(keyA), [legacy], approvals: [IdentityApproval(group: home, key: keyA, recordID: legacy.id)]) == .damaged)
    }

    @Test func anUnapprovedRouterAsksAmongBoundForgottenAndLegacyButNeverTheBucket() {
        let bound = record(.bound)
        let forgotten = record(.forgotten)
        let legacy = record(.legacyUnverified)
        let bucket = record(.bucket)
        let approvals = [IdentityApproval(group: home, key: keyA, recordID: bound.id)]
        #expect(
            resolve(.present(keyB), [bound, forgotten, legacy, bucket], approvals: approvals)
                == .ask(.whichNetwork(group: home, key: keyB, options: [bound.id, forgotten.id, legacy.id]))
        )
    }

    /// #645: after a start over, a group can hold several legacy networks (a split-off one among
    /// them): every one is offered, in both hint states, never only the first.
    @Test func severalLegacyNetworksAreAllOffered() {
        let first = record(.legacyUnverified)
        let split = record(.legacyUnverified)
        #expect(resolve(.present(keyA), [first, split]) == .ask(.whichNetwork(group: home, key: keyA, options: [first.id, split.id])))
        #expect(resolve(.absent, [first, split]) == .ask(.forgottenThisConnection(group: home, options: [first.id, split.id])))
    }

    @Test func anUnboundLegacyRecordIsProbedForOverlap() {
        let legacy = record(.legacyUnverified)
        let bucket = record(.bucket)
        #expect(resolve(.present(keyA), [legacy, bucket]) == .probeLegacy(legacy.id, keyA))
    }

    @Test func aNewRouterInAGroupWithNoHistoryMakesANewNetwork() {
        #expect(resolve(.present(keyA), []) == .create(keyA))
        #expect(resolve(.present(keyA), [record(.bucket)]) == .create(keyA))
    }
}

@Suite("Legacy overlap")
struct LegacyOverlapTests {
    typealias Seen = LegacyOverlap.Observation
    typealias Saved = LegacyOverlap.SavedDevice

    let gateway = "192.168.1.1"

    private var savedHome: [Saved] {
        [
            Saved(deviceID: UUID(), ipAddress: "192.168.1.1", macAddress: nil, name: "rt-ax86u-7c10"),
            Saved(deviceID: UUID(), ipAddress: "192.168.1.20", macAddress: nil, name: "office-printer"),
            Saved(deviceID: UUID(), ipAddress: "192.168.1.30", macAddress: nil, name: "Backup-NAS.local"),
            Saved(deviceID: UUID(), ipAddress: "192.168.1.40", macAddress: "00:1B:A9:00:00:40", name: nil)
        ]
    }

    @Test func theGatewayAndTwoOthersMatchingBindQuietly() {
        let seen = [
            Seen(ipAddress: "192.168.1.1", macAddress: nil, name: "RT-AX86U-7C10.local."),
            Seen(ipAddress: "192.168.1.20", macAddress: nil, name: "office-printer.lan"),
            Seen(ipAddress: "192.168.1.30", macAddress: nil, name: "backup-nas")
        ]
        #expect(LegacyOverlap.isClear(gatewayIP: gateway, observed: seen, saved: savedHome))
    }

    @Test func travellingDevicesWithoutTheGatewayAsk() {
        let seen = [
            Seen(ipAddress: "192.168.1.1", macAddress: nil, name: "another-router"),
            Seen(ipAddress: "192.168.1.20", macAddress: nil, name: "office-printer"),
            Seen(ipAddress: "192.168.1.30", macAddress: nil, name: "backup-nas"),
            Seen(ipAddress: "192.168.1.41", macAddress: "00:1B:A9:00:00:40", name: nil)
        ]
        #expect(!LegacyOverlap.isClear(gatewayIP: gateway, observed: seen, saved: savedHome))
    }

    @Test func aGatewayWithAGenericOrNoNameAsks() {
        let saved = [Saved(deviceID: UUID(), ipAddress: "192.168.1.1", macAddress: nil, name: "router")] + Array(savedHome.dropFirst())
        let seen = [
            Seen(ipAddress: "192.168.1.1", macAddress: nil, name: "router"),
            Seen(ipAddress: "192.168.1.20", macAddress: nil, name: "office-printer"),
            Seen(ipAddress: "192.168.1.30", macAddress: nil, name: "backup-nas")
        ]
        #expect(!LegacyOverlap.isClear(gatewayIP: gateway, observed: seen, saved: saved))
        let nameless = [Seen(ipAddress: "192.168.1.1", macAddress: nil, name: nil)] + Array(seen.dropFirst())
        #expect(!LegacyOverlap.isClear(gatewayIP: gateway, observed: nameless, saved: savedHome))
    }

    @Test func aDeviceIsCountedOnceWhateverItsInterfaces() {
        let nas = UUID()
        let saved = [
            savedHome[0],
            Saved(deviceID: nas, ipAddress: "192.168.1.30", macAddress: nil, name: "backup-nas"),
            Saved(deviceID: nas, ipAddress: "192.168.1.31", macAddress: nil, name: "backup-nas-2")
        ]
        let seen = [
            Seen(ipAddress: "192.168.1.1", macAddress: nil, name: "rt-ax86u-7c10"),
            Seen(ipAddress: "192.168.1.30", macAddress: nil, name: "backup-nas"),
            Seen(ipAddress: "192.168.1.31", macAddress: nil, name: "backup-nas-2")
        ]
        #expect(!LegacyOverlap.isClear(gatewayIP: gateway, observed: seen, saved: saved))
    }

    @Test func aPrivateMACIsNotARealMatch() {
        let saved = [
            savedHome[0],
            Saved(deviceID: UUID(), ipAddress: "192.168.1.50", macAddress: "02:00:00:00:00:50", name: nil),
            Saved(deviceID: UUID(), ipAddress: "192.168.1.51", macAddress: "06:00:00:00:00:51", name: nil)
        ]
        let seen = [
            Seen(ipAddress: "192.168.1.1", macAddress: nil, name: "rt-ax86u-7c10"),
            Seen(ipAddress: "192.168.1.50", macAddress: "02:00:00:00:00:50", name: nil),
            Seen(ipAddress: "192.168.1.51", macAddress: "06:00:00:00:00:51", name: nil)
        ]
        #expect(!LegacyOverlap.isClear(gatewayIP: gateway, observed: seen, saved: saved))
    }

    @Test func aRealMACMatchesAtAnyAddress() {
        let seen = [
            Seen(ipAddress: "192.168.1.1", macAddress: nil, name: "rt-ax86u-7c10"),
            Seen(ipAddress: "192.168.1.20", macAddress: nil, name: "office-printer"),
            Seen(ipAddress: "192.168.1.99", macAddress: "00:1b:a9:00:00:40", name: nil)
        ]
        #expect(LegacyOverlap.isClear(gatewayIP: gateway, observed: seen, saved: savedHome))
    }

    @Test func namesAreNormalisedAsTheContractSays() {
        #expect(LegacyOverlap.normalizedName("Backup-NAS.local.") == "backup-nas")
        #expect(LegacyOverlap.normalizedName("office-printer.home.lan") == "office-printer")
        #expect(LegacyOverlap.normalizedName("  OFFICEPC ") == "officepc")
        #expect(LegacyOverlap.normalizedName("router") == nil)
        #expect(LegacyOverlap.normalizedName("") == nil)
    }
}
