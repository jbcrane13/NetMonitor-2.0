import Testing
import Foundation
@testable import NetMonitorCore

@Suite("NetworkHealthChecklist")
struct NetworkHealthChecklistTests {

    private func check(_ kind: HealthCheck.Kind, in inputs: HealthCheckInputs) -> HealthCheck? {
        NetworkHealthChecklist.evaluate(inputs).first { $0.kind == kind }
    }

    @Test func emptyInputsProduceNoRows() {
        #expect(NetworkHealthChecklist.evaluate(HealthCheckInputs()).isEmpty)
    }

    @Test func allHealthyInputsPassInFixedOrder() {
        let inputs = HealthCheckInputs(
            gatewayReachable: true,
            dnsServers: ["192.168.1.1"],
            internetReachable: true,
            vpnActive: false,
            wifiRSSI: -45,
            deviceCount: 12,
            linkSpeedMbps: 866
        )
        let checks = NetworkHealthChecklist.evaluate(inputs)
        #expect(checks.map(\.kind) == HealthCheck.Kind.allCases)
        #expect(checks.allSatisfy { $0.status == .pass })
        #expect(checks.allSatisfy { !$0.message.isEmpty })
    }

    @Test func unreachableGatewayWarns() {
        #expect(check(.gateway, in: HealthCheckInputs(gatewayReachable: false))?.status == .warn)
    }

    @Test func unreachableInternetWarns() {
        #expect(check(.internet, in: HealthCheckInputs(internetReachable: false))?.status == .warn)
    }

    @Test func noDNSServersWarns() {
        #expect(check(.dnsServers, in: HealthCheckInputs(dnsServers: []))?.status == .warn)
    }

    @Test func unreadableDNSConfigOmitsRow() {
        #expect(check(.dnsServers, in: HealthCheckInputs(dnsServers: nil)) == nil)
    }

    @Test func dnsMessageListsAtMostTwoServers() throws {
        let row = try #require(check(.dnsServers, in: HealthCheckInputs(dnsServers: ["1.1.1.1", "8.8.8.8", "9.9.9.9"])))
        #expect(row.status == .pass)
        #expect(row.message.contains("3 DNS servers"))
        #expect(!row.message.contains("9.9.9.9"))
    }

    @Test func vpnOnWarnsAndOffPasses() {
        #expect(check(.vpn, in: HealthCheckInputs(vpnActive: true))?.status == .warn)
        #expect(check(.vpn, in: HealthCheckInputs(vpnActive: false))?.status == .pass)
    }

    @Test(arguments: [(-45, HealthCheck.Status.pass), (-58, .pass), (-65, .warn), (-80, .warn)])
    func wifiSignalUsesRSSIQualityTiers(rssi: Int, expected: HealthCheck.Status) {
        #expect(check(.wifiSignal, in: HealthCheckInputs(wifiRSSI: rssi))?.status == expected)
    }

    @Test func missingWiFiAndLinkSpeedOmitRows() {
        let checks = NetworkHealthChecklist.evaluate(HealthCheckInputs(gatewayReachable: true, deviceCount: 3))
        #expect(!checks.contains { $0.kind == .wifiSignal })
        #expect(!checks.contains { $0.kind == .linkSpeed })
    }

    @Test func zeroLinkSpeedIsTreatedAsUnknown() {
        #expect(check(.linkSpeed, in: HealthCheckInputs(linkSpeedMbps: 0)) == nil)
    }

    @Test func slowLinkSpeedWarns() {
        #expect(check(.linkSpeed, in: HealthCheckInputs(linkSpeedMbps: 24))?.status == .warn)
        #expect(check(.linkSpeed, in: HealthCheckInputs(linkSpeedMbps: 50))?.status == .pass)
    }

    @Test func zeroDevicesWarns() {
        #expect(check(.devices, in: HealthCheckInputs(deviceCount: 0))?.status == .warn)
        #expect(check(.devices, in: HealthCheckInputs(deviceCount: 1))?.message == "1 device found on your network.")
    }
}

@Suite("SystemDNSConfiguration")
struct SystemDNSConfigurationTests {

    @Test func parsesNameserversInOrderAndIgnoresOtherLines() {
        let conf = """
        #
        # macOS Notice
        domain lan
        nameserver 192.168.1.1
        nameserver\tfe80::1%en0
        search lan
        nameserver 8.8.8.8
        """
        #expect(SystemDNSConfiguration.nameservers(fromResolvConf: conf) == ["192.168.1.1", "fe80::1%en0", "8.8.8.8"])
    }

    @Test func emptyFileHasNoNameservers() {
        #expect(SystemDNSConfiguration.nameservers(fromResolvConf: "").isEmpty)
    }

    @Test func missingFileReturnsNil() {
        #expect(SystemDNSConfiguration.currentNameservers(path: "/nonexistent/resolv.conf") == nil)
    }
}
