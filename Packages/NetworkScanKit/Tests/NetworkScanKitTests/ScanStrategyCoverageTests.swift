import Foundation
import Testing
@testable import NetworkScanKit

/// Direct tests for ScanStrategy and NetworkScanProfile, covering
/// enum conformance, equality, and init parameters.
@Suite("ScanStrategy coverage")
struct ScanStrategyCoverageTests {

    // MARK: - ScanStrategy enum cases

    @Test("ScanStrategy.full exists and is equatable")
    func fullCase() {
        let strategy: ScanStrategy = .full
        #expect(strategy == .full)
        #expect(strategy != .remote)
    }

    @Test("ScanStrategy.remote exists and is equatable")
    func remoteCase() {
        let strategy: ScanStrategy = .remote
        #expect(strategy == .remote)
        #expect(strategy != .full)
    }

    @Test("ScanStrategy is Sendable")
    func sendableConformance() {
        // Compile-time check: assigning to a @Sendable closure
        let strategy: ScanStrategy = .full
        let closure: @Sendable () -> ScanStrategy = { strategy }
        #expect(closure() == .full)
    }

    @Test("ScanStrategy can be used in switch statements exhaustively")
    func switchExhaustiveness() {
        func describe(_ strategy: ScanStrategy) -> String {
            switch strategy {
            case .full: return "full"
            case .remote: return "remote"
            }
        }
        #expect(describe(.full) == "full")
        #expect(describe(.remote) == "remote")
    }

    @Test("ScanStrategy equality is reflexive")
    func equalityReflexive() {
        #expect(ScanStrategy.full == ScanStrategy.full)
        #expect(ScanStrategy.remote == ScanStrategy.remote)
    }

    @Test("ScanStrategy equality is symmetric")
    func equalitySymmetric() {
        #expect(ScanStrategy.full != ScanStrategy.remote)
        #expect(ScanStrategy.remote != ScanStrategy.full)
    }

    // MARK: - NetworkScanProfile

    @Test("NetworkScanProfile init with all parameters")
    func profileInitWithAllParameters() {
        let profile = NetworkScanProfile(
            id: "home-net",
            name: "Home Network",
            subnetCIDR: "192.168.1.0/24"
        )
        #expect(profile.id == "home-net")
        #expect(profile.name == "Home Network")
        #expect(profile.subnetCIDR == "192.168.1.0/24")
    }

    @Test("NetworkScanProfile init with nil subnetCIDR")
    func profileInitWithNilSubnetCIDR() {
        let profile = NetworkScanProfile(
            id: "office",
            name: "Office"
        )
        #expect(profile.id == "office")
        #expect(profile.name == "Office")
        #expect(profile.subnetCIDR == nil)
    }

    @Test("NetworkScanProfile default subnetCIDR is nil")
    func profileDefaultSubnetCIDR() {
        let profile = NetworkScanProfile(id: "test", name: "Test")
        #expect(profile.subnetCIDR == nil)
    }

    @Test("NetworkScanProfile is Identifiable")
    func profileIsIdentifiable() {
        let profile = NetworkScanProfile(id: "unique-id", name: "Test")
        #expect(profile.id == "unique-id")
    }

    @Test("NetworkScanProfile equality - same values are equal")
    func profileEqualitySameValues() {
        let profile1 = NetworkScanProfile(id: "a", name: "Net", subnetCIDR: "10.0.0.0/8")
        let profile2 = NetworkScanProfile(id: "a", name: "Net", subnetCIDR: "10.0.0.0/8")
        #expect(profile1 == profile2)
    }

    @Test("NetworkScanProfile equality - different IDs are not equal")
    func profileEqualityDifferentIDs() {
        let profile1 = NetworkScanProfile(id: "a", name: "Net")
        let profile2 = NetworkScanProfile(id: "b", name: "Net")
        #expect(profile1 != profile2)
    }

    @Test("NetworkScanProfile equality - different names are not equal")
    func profileEqualityDifferentNames() {
        let profile1 = NetworkScanProfile(id: "a", name: "Net1")
        let profile2 = NetworkScanProfile(id: "a", name: "Net2")
        #expect(profile1 != profile2)
    }

    @Test("NetworkScanProfile equality - different subnetCIDR are not equal")
    func profileEqualityDifferentSubnetCIDR() {
        let profile1 = NetworkScanProfile(id: "a", name: "Net", subnetCIDR: "10.0.0.0/8")
        let profile2 = NetworkScanProfile(id: "a", name: "Net", subnetCIDR: "192.168.0.0/16")
        #expect(profile1 != profile2)
    }

    @Test("NetworkScanProfile equality - nil vs non-nil subnetCIDR are not equal")
    func profileEqualityNilVsNonNilSubnetCIDR() {
        let profile1 = NetworkScanProfile(id: "a", name: "Net")
        let profile2 = NetworkScanProfile(id: "a", name: "Net", subnetCIDR: "10.0.0.0/8")
        #expect(profile1 != profile2)
    }

    @Test("NetworkScanProfile is Sendable")
    func profileSendable() {
        let profile = NetworkScanProfile(id: "s", name: "Sendable")
        let closure: @Sendable () -> NetworkScanProfile = { profile }
        #expect(closure().id == "s")
    }

    // MARK: - ScanContext with NetworkScanProfile and ScanStrategy

    @Test("ScanContext with .remote strategy and profile")
    func contextWithRemoteStrategyAndProfile() {
        let profile = NetworkScanProfile(id: "remote-office", name: "Remote Office", subnetCIDR: "10.10.0.0/16")
        let ctx = ScanContext(
            hosts: ["10.10.0.1"],
            subnetFilter: { _ in true },
            localIP: nil,
            networkProfile: profile,
            scanStrategy: .remote
        )
        #expect(ctx.scanStrategy == .remote)
        #expect(ctx.networkProfile?.id == "remote-office")
        #expect(ctx.networkProfile?.subnetCIDR == "10.10.0.0/16")
    }

    @Test("ScanContext with .full strategy and nil profile")
    func contextWithFullStrategyNilProfile() {
        let ctx = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: "192.168.1.100",
            scanStrategy: .full
        )
        #expect(ctx.scanStrategy == .full)
        #expect(ctx.networkProfile == nil)
        #expect(ctx.localIP == "192.168.1.100")
    }

    @Test("ScanContext subnetFilter with complex logic")
    func contextSubnetFilterComplex() {
        let allowedSubnets = ["192.168.1.", "10.0.0."]
        let ctx = ScanContext(
            hosts: [],
            subnetFilter: { ip in allowedSubnets.contains { ip.hasPrefix($0) } },
            localIP: nil
        )
        #expect(ctx.subnetFilter("192.168.1.50") == true)
        #expect(ctx.subnetFilter("10.0.0.99") == true)
        #expect(ctx.subnetFilter("172.16.0.1") == false)
        #expect(ctx.subnetFilter("192.168.2.1") == false)
    }

    @Test("ScanContext with many hosts")
    func contextWithManyHosts() {
        let hosts = (1...254).map { "192.168.1.\($0)" }
        let ctx = ScanContext(hosts: hosts, subnetFilter: { _ in true }, localIP: "192.168.1.100")
        #expect(ctx.hosts.count == 254)
        #expect(ctx.hosts.contains("192.168.1.1"))
        #expect(ctx.hosts.contains("192.168.1.254"))
        #expect(ctx.localIP == "192.168.1.100")
    }
}
