import Testing
@testable import NetworkScanKit

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

    // MARK: - ScanStrategy

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
        let ctx = ScanContext(
            hosts: ["10.0.0.1"],
            subnetFilter: { ip in ip.hasPrefix("10.0.") },
            localIP: "10.0.0.50",
            scanStrategy: .remote
        )

        #expect(ctx.hosts == ["10.0.0.1"])
        #expect(ctx.subnetFilter("10.0.0.1") == true)
        #expect(ctx.localIP == "10.0.0.50")
        #expect(ctx.scanStrategy == .remote)
    }
}
