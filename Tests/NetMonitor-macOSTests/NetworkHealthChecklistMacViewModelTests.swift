import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_macOS

/// Answers pings per host: hosts in `replying` reply, every other host times out.
private final class HostPingService: PingServiceProtocol, @unchecked Sendable {
    let replying: Set<String>
    private(set) var hosts: [String] = []

    init(replying: Set<String>) {
        self.replying = replying
    }

    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        hosts.append(host)
        let ok = replying.contains(host)
        return AsyncStream { continuation in
            for seq in 1...count {
                continuation.yield(PingResult(sequence: seq, host: host, ttl: 64, time: ok ? 12 : 0, isTimeout: !ok))
            }
            continuation.finish()
        }
    }

    func stop() async {}
    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? { nil }
}

private final class StubVPNService: VPNDetectionServiceProtocol, @unchecked Sendable {
    var isActive = false
    var status: VPNStatus { VPNStatus(isActive: isActive) }
    func startMonitoring() {}
    func stopMonitoring() {}
    func statusStream() -> AsyncStream<VPNStatus> { AsyncStream { $0.finish() } }
}

@Suite("NetworkHealthScoreMacViewModel checklist (#397, #399)")
@MainActor
struct NetworkHealthChecklistMacViewModelTests {

    private func makeVM(
        ping: HostPingService,
        dnsServers: HealthCheckInputs.DNSServers = .servers(["192.168.1.1"]),
        lookup: @escaping DNSServerBenchmark.Lookup = { _, _, _ in nil }
    ) -> NetworkHealthScoreMacViewModel {
        NetworkHealthScoreMacViewModel(
            service: NetworkHealthScoreService(),
            pingService: ping,
            vpnService: StubVPNService(),
            readDNSServers: { dnsServers },
            dnsBenchmark: DNSServerBenchmark(domains: ["a.com"], tries: 1, lookup: lookup)
        )
    }

    @Test func gatewayIsPingedAndUnansweredRouterWarns() async {
        let ping = HostPingService(replying: ["8.8.8.8"])
        let vm = makeVM(ping: ping)
        await vm.refresh(gatewayIP: "192.168.1.1")

        #expect(ping.hosts == ["8.8.8.8", "192.168.1.1"])
        #expect(vm.checks.first { $0.kind == .gateway }?.status == .warn)
        #expect(vm.checks.first { $0.kind == .internet }?.status == .pass)
        #expect(vm.checks.first { $0.kind == .vpn }?.status == .pass)
        #expect(vm.checks.first { $0.kind == .dnsServers }?.status == .pass)
    }

    @Test func noGatewayIPSkipsRouterRowAndPing() async {
        let ping = HostPingService(replying: [])
        let vm = makeVM(ping: ping, dnsServers: .unavailable)
        await vm.refresh()

        #expect(ping.hosts == ["8.8.8.8"])
        #expect(!vm.checks.contains { $0.kind == .gateway })
        #expect(vm.checks.first { $0.kind == .dnsServers }?.status == .unavailable)
        #expect(vm.checks.first { $0.kind == .internet }?.status == .warn)
    }

    @Test func localWiFiAndDeviceInputsBecomeRows() async {
        let vm = makeVM(ping: HostPingService(replying: ["8.8.8.8", "10.0.0.1"]))
        await vm.refresh(
            gatewayIP: "10.0.0.1",
            localInputs: HealthCheckInputs(wifiRSSI: -72, deviceCount: 4, linkSpeedMbps: 24)
        )

        #expect(vm.checks.first { $0.kind == .gateway }?.status == .pass)
        #expect(vm.checks.first { $0.kind == .wifiSignal }?.status == .warn)
        #expect(vm.checks.first { $0.kind == .devices }?.status == .pass)
        #expect(vm.checks.first { $0.kind == .linkSpeed }?.status == .warn)
    }

    @Test func compareDNSServersPicksFastestResponder() async {
        let vm = makeVM(ping: HostPingService(replying: [])) { _, server, _ in
            server == "9.9.9.9" ? 5 : 40
        }
        await vm.compareDNSServers()

        #expect(vm.dnsResults.count == 4)
        #expect(vm.fastestDNS?.server.address == "9.9.9.9")
    }
}
