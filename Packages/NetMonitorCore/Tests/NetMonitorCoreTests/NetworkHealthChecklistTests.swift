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
            dnsServers: .servers(["192.168.1.1"]),
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
        #expect(check(.dnsServers, in: HealthCheckInputs(dnsServers: .servers([])))?.status == .warn)
    }

    @Test func unmeasuredDNSOmitsRow() {
        #expect(check(.dnsServers, in: HealthCheckInputs(dnsServers: nil)) == nil)
    }

    @Test func unavailableDNSIsLabelledNotGuessed() throws {
        let row = try #require(check(.dnsServers, in: HealthCheckInputs(dnsServers: .unavailable)))
        #expect(row.status == .unavailable)
        #expect(row.message == "Configured DNS unavailable on this device.")
    }

    @Test func dnsMessageListsAtMostTwoServers() throws {
        let row = try #require(check(.dnsServers, in: HealthCheckInputs(dnsServers: .servers(["1.1.1.1", "8.8.8.8", "9.9.9.9"]))))
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

    @Test func loopbackOnlyResolverAnswerIsUnavailable() {
        #expect(SystemDNSConfiguration.usable(["127.0.0.1"]) == .unavailable)
        #expect(SystemDNSConfiguration.usable([]) == .unavailable)
    }

    @Test func realServersAreKeptInOrder() {
        #expect(SystemDNSConfiguration.usable(["192.168.1.1", "::1"]) == .servers(["192.168.1.1", "::1"]))
    }

    @Test func currentReadsThePlatformSourceWithoutCrashing() {
        // Runs against the test host's real configuration; either outcome is valid.
        switch SystemDNSConfiguration.current() {
        case let .servers(servers): #expect(!servers.isEmpty)
        case .unavailable: break
        }
    }
}
