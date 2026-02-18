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
}
