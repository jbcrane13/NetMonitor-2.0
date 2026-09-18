import Testing
@testable import NetworkScanKit

struct ScanContextTests {

    @Test("init stores hosts correctly")
    func storesHosts() {
        let hosts = ["192.168.1.1", "192.168.1.2", "10.0.0.1"]
        let ctx = ScanContext(hosts: hosts, subnetFilter: { _ in true }, localIP: nil, requiredInterfaceType: .wifi)
        #expect(ctx.hosts == hosts)
    }

    @Test("subnetFilter is callable and works as provided")
    func subnetFilterCallable() {
        let ctx = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { ip in ip.hasPrefix("192.168.") },
            localIP: nil,
            requiredInterfaceType: .wifi
        )
        #expect(ctx.subnetFilter("192.168.1.100") == true)
        #expect(ctx.subnetFilter("10.0.0.1") == false)
    }

    @Test("localIP is stored when provided")
    func localIPStored() {
        let ctx = ScanContext(hosts: [], subnetFilter: { _ in false }, localIP: "192.168.1.50", requiredInterfaceType: .wifi)
        #expect(ctx.localIP == "192.168.1.50")
    }

    @Test("localIP is nil when not provided")
    func localIPNil() {
        let ctx = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil, requiredInterfaceType: .wifi)
        #expect(ctx.localIP == nil)
    }

    @Test("empty hosts array")
    func emptyHosts() {
        let ctx = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil, requiredInterfaceType: .wifi)
        #expect(ctx.hosts.isEmpty)
    }

    @Test("always-false subnet filter")
    func alwaysFalseFilter() {
        let ctx = ScanContext(hosts: ["192.168.1.1"], subnetFilter: { _ in false }, localIP: nil, requiredInterfaceType: .wifi)
        #expect(ctx.subnetFilter("192.168.1.1") == false)
    }

    @Test("full context with all parameters")
    func fullContext() {
        let ctx = ScanContext(
            hosts: ["10.0.0.1"],
            subnetFilter: { ip in ip.hasPrefix("10.0.") },
            localIP: "10.0.0.50",
            requiredInterfaceType: .wifi
        )

        #expect(ctx.hosts == ["10.0.0.1"])
        #expect(ctx.subnetFilter("10.0.0.1") == true)
        #expect(ctx.localIP == "10.0.0.50")
    }

    // MARK: - requiredInterfaceType (D15)

    @Test("requiredInterfaceType defaults to nil when omitted — a wired Mac must still discover")
    func requiredInterfaceTypeDefaultsToNil() {
        let ctx = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil)
        #expect(ctx.requiredInterfaceType == nil)
    }

    @Test("requiredInterfaceType stores an explicit .wifi value — iOS behaviour is unchanged")
    func requiredInterfaceTypeStoresWifi() {
        let ctx = ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil, requiredInterfaceType: .wifi)
        #expect(ctx.requiredInterfaceType == .wifi)
    }
}
