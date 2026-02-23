import Testing
@testable import NetworkScanKit

@Suite("ScanContext")
struct ScanContextTests {

    @Test("init stores hosts correctly")
    func storesHosts() {
        let hosts = ["192.168.1.1", "192.168.1.2", "10.0.0.1"]
        let ctx = ScanContext(hosts: hosts, subnetFilter: { _ in true }, localIP: nil)
        #expect(ctx.hosts == hosts)
    }

    @Test("subnetFilter is callable and works as provided")
    func subnetFilterCallable() {
        let ctx = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { ip in ip.hasPrefix("192.168.") },
            localIP: nil
        )
        #expect(ctx.subnetFilter("192.168.1.100") == true)
        #expect(ctx.subnetFilter("10.0.0.1") == false)
    }

    @Test("localIP is stored when provided")
    func localIPStored() {
        let ctx = ScanContext(hosts: [], subnetFilter: { _ in false }, localIP: "192.168.1.50")
        #expect(ctx.localIP == "192.168.1.50")
    }

    @Test("localIP is nil when not provided")
    func localIPNil() {
        let ctx = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil)
        #expect(ctx.localIP == nil)
    }

    @Test("empty hosts array")
    func emptyHosts() {
        let ctx = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil)
        #expect(ctx.hosts.isEmpty)
    }

    @Test("always-false subnet filter")
    func alwaysFalseFilter() {
        let ctx = ScanContext(hosts: ["192.168.1.1"], subnetFilter: { _ in false }, localIP: nil)
        #expect(ctx.subnetFilter("192.168.1.1") == false)
    }

    // MARK: - NetworkProfile and ScanStrategy

    @Test("networkProfile defaults to nil")
    func networkProfileDefaultsToNil() {
        let ctx = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil)
        #expect(ctx.networkProfile == nil)
    }

    @Test("networkProfile is stored when provided")
    func networkProfileStored() {
        let profile = NetworkProfile(id: "home-5ghz", name: "Home 5GHz", subnetCIDR: "192.168.1.0/24")
        let ctx = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil,
            networkProfile: profile
        )
        #expect(ctx.networkProfile?.id == "home-5ghz")
        #expect(ctx.networkProfile?.name == "Home 5GHz")
        #expect(ctx.networkProfile?.subnetCIDR == "192.168.1.0/24")
    }

    @Test("scanStrategy defaults to .full")
    func scanStrategyDefaultsToFull() {
        let ctx = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil)
        #expect(ctx.scanStrategy == .full)
    }

    @Test("scanStrategy can be set to .remote")
    func scanStrategyCanBeRemote() {
        let ctx = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil,
            scanStrategy: .remote
        )
        #expect(ctx.scanStrategy == .remote)
    }

    @Test("scanStrategy can be set to .full explicitly")
    func scanStrategyCanBeFullExplicit() {
        let ctx = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil,
            scanStrategy: .full
        )
        #expect(ctx.scanStrategy == .full)
    }

    @Test("full context with all parameters")
    func fullContext() {
        let profile = NetworkProfile(id: "office", name: "Office Network")
        let ctx = ScanContext(
            hosts: ["10.0.0.1"],
            subnetFilter: { ip in ip.hasPrefix("10.0.") },
            localIP: "10.0.0.50",
            networkProfile: profile,
            scanStrategy: .remote
        )

        #expect(ctx.hosts == ["10.0.0.1"])
        #expect(ctx.subnetFilter("10.0.0.1") == true)
        #expect(ctx.localIP == "10.0.0.50")
        #expect(ctx.networkProfile?.id == "office")
        #expect(ctx.scanStrategy == .remote)
    }
}
