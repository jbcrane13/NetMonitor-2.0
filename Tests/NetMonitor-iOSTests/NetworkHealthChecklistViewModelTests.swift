import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

private final class StubVPNService: VPNDetectionServiceProtocol, @unchecked Sendable {
    var isActive = false
    var startCallCount = 0
    var status: VPNStatus { VPNStatus(isActive: isActive) }
    func startMonitoring() { startCallCount += 1 }
    func stopMonitoring() {}
    func statusStream() -> AsyncStream<VPNStatus> { AsyncStream { $0.finish() } }
}

@Suite("NetworkHealthScoreViewModel checklist (#397, #399)")
@MainActor
struct NetworkHealthChecklistViewModelTests {

    private func makeVM(
        pingResults: [PingResult],
        vpn: StubVPNService = StubVPNService(),
        dnsServers: HealthCheckInputs.DNSServers = .servers(["192.168.1.1"]),
        lookup: @escaping DNSServerBenchmark.Lookup = { _, _, _ in nil }
    ) -> NetworkHealthScoreViewModel {
        let ping = MockPingService()
        ping.mockResults = pingResults
        return NetworkHealthScoreViewModel(
            service: NetworkHealthScoreService(),
            pingService: ping,
            networkMonitor: MockNetworkMonitorService(),
            vpnService: vpn,
            readDNSServers: { dnsServers },
            dnsBenchmark: DNSServerBenchmark(domains: ["a.com"], tries: 1, lookup: lookup)
        )
    }

    private func reply(_ seq: Int, ms: Double = 20, timeout: Bool = false) -> PingResult {
        PingResult(sequence: seq, host: "8.8.8.8", ttl: 64, time: ms, isTimeout: timeout)
    }

    @Test func refreshBuildsChecklistFromLocalAndMeasuredInputs() async {
        let vpn = StubVPNService()
        let vm = makeVM(pingResults: [reply(1), reply(2)], vpn: vpn)
        vm.refresh(localInputs: HealthCheckInputs(gatewayReachable: true, wifiRSSI: -48, deviceCount: 7, linkSpeedMbps: 400))
        await waitUntil { !vm.checks.isEmpty }

        #expect(vm.checks.map(\.kind) == HealthCheck.Kind.allCases)
        #expect(vm.checks.allSatisfy { $0.status == .pass })
        #expect(vpn.startCallCount == 1)
    }

    @Test func failedPingsWarnInternetAndActiveVPNWarns() async {
        let vpn = StubVPNService()
        vpn.isActive = true
        let vm = makeVM(pingResults: [reply(1, timeout: true), reply(2, timeout: true)], vpn: vpn, dnsServers: .servers([]))
        vm.refresh()
        await waitUntil { !vm.checks.isEmpty }

        #expect(vm.checks.first { $0.kind == .internet }?.status == .warn)
        #expect(vm.checks.first { $0.kind == .vpn }?.status == .warn)
        #expect(vm.checks.first { $0.kind == .dnsServers }?.status == .warn)
        #expect(!vm.checks.contains { $0.kind == .wifiSignal })
    }

    @Test func compareDNSServersTimesCurrentAndPublicServers() async {
        let vm = makeVM(pingResults: [], dnsServers: .servers(["192.168.1.1"])) { _, server, _ in
            server == "1.1.1.1" ? 8 : (server == "192.168.1.1" ? nil : 30)
        }
        await vm.compareDNSServers()

        #expect(vm.dnsResults.map(\.server.address) == ["192.168.1.1", "1.1.1.1", "8.8.8.8", "9.9.9.9"])
        #expect(vm.dnsResults.first?.medianMs == nil)
        #expect(vm.fastestDNS?.server.name == "Cloudflare")
        #expect(vm.isComparingDNS == false)
    }
}
