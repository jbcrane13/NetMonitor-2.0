import Testing
@testable import NetMonitorCore

/// With Tailscale on, the system resolver knows no LAN names, so the gateway's DNS is asked.
struct GatewayNameResolverTests {

    @Test("Asks the gateway's DNS when the system resolver finds nothing")
    func fallsBackToGateway() async {
        let resolver = GatewayNameResolver(
            system: { _ in nil },
            gateway: { "192.168.2.1" },
            query: { name, server in
                name == "4.2.168.192.in-addr.arpa" && server == "192.168.2.1" ? "u7-pro.lan.windingbrook.net." : nil
            }
        )
        #expect(await resolver.resolve(ipAddress: "192.168.2.4") == "u7-pro.lan.windingbrook.net")
    }

    @Test("Uses the system's answer without asking the gateway")
    func systemFirst() async {
        let resolver = GatewayNameResolver(
            system: { _ in "mini-pro-1.lan.windingbrook.net" },
            gateway: { "192.168.2.1" },
            query: { _, _ in
                Issue.record("gateway asked")
                return nil
            }
        )
        #expect(await resolver.resolve(ipAddress: "192.168.2.16") == "mini-pro-1.lan.windingbrook.net")
    }

    @Test("Nothing when there is no gateway or no answer")
    func noAnswer() async {
        let noGateway = GatewayNameResolver(system: { _ in nil }, gateway: { nil }, query: { _, _ in "x" })
        #expect(await noGateway.resolve(ipAddress: "192.168.2.4") == nil)
        let noRecord = GatewayNameResolver(system: { _ in nil }, gateway: { "192.168.2.1" }, query: { _, _ in nil })
        #expect(await noRecord.resolve(ipAddress: "192.168.2.4") == nil)
    }
}
