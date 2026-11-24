import Testing
import Foundation
import CoreLocation
@testable import NetMonitorCore

private final class StubPing: PingServiceProtocol, @unchecked Sendable {
    var results: [PingResult] = []
    var stopped = false
    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        let results = results
        return AsyncStream { continuation in
            results.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func stop() async { stopped = true }
    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? { nil }
}

private final class StubPorts: PortScannerServiceProtocol, @unchecked Sendable {
    func scan(host: String, ports: [Int], timeout: TimeInterval) async -> AsyncStream<PortScanResult> {
        AsyncStream { continuation in
            for port in ports {
                continuation.yield(PortScanResult(port: port, state: port == 443 ? .open : .closed))
            }
            continuation.finish()
        }
    }

    func stop() async {}
}

@MainActor
private final class StubDNS: DNSLookupServiceProtocol, @unchecked Sendable {
    var result: DNSQueryResult?
    var isLoading = false
    var lastError: String?
    func lookup(domain: String, recordType: DNSRecordType, server: String?) async -> DNSQueryResult? { result }
    func lookupAll(domain: String, server: String?) async -> DNSQueryResult? { result }
}

@MainActor
private final class StubWiFi: WiFiInfoServiceProtocol, @unchecked Sendable {
    var info: WiFiInfo?
    var currentWiFi: WiFiInfo? { info }
    var isLocationAuthorized = true
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    func requestLocationPermission() {}
    func refreshWiFiInfo() {}
    func fetchCurrentWiFi() async -> WiFiInfo? { info }
}

/// The live checks over the app's services (#451).
@Suite("ServiceTroubleshootProbes")
@MainActor
struct ServiceTroubleshootProbesTests {
    private func probes(ping: StubPing = StubPing(), dns: StubDNS? = nil, wifi: StubWiFi? = nil,
                        canRunSpeedTest: Bool = true) -> ServiceTroubleshootProbes {
        ServiceTroubleshootProbes(
            pingService: ping, portScanner: StubPorts(), dnsService: dns ?? StubDNS(), wifiService: wifi ?? StubWiFi(),
            gateway: { "10.0.0.1" }, canRunSpeedTest: { canRunSpeedTest }
        )
    }

    private func result(_ sequence: Int, _ time: Double, timeout: Bool = false) -> PingResult {
        PingResult(sequence: sequence, host: "10.0.0.1", ttl: 64, time: time, isTimeout: timeout)
    }

    @Test func pingKeepsTheRepliesRoundTrips() async {
        let ping = StubPing()
        ping.results = [result(1, 3.5), result(2, 0, timeout: true), result(3, 4.5)]
        #expect(await probes(ping: ping).ping("10.0.0.1", count: 3) == [3.5, 4.5])
    }

    @Test func aLookupWithoutRecordsDidNotResolve() async {
        let dns = StubDNS()
        dns.result = DNSQueryResult(domain: "a.com", server: "1.1.1.1", queryType: .a, records: [], queryTime: 12)
        #expect(await probes(dns: dns).lookup("a.com") == nil)
        dns.result = DNSQueryResult(domain: "a.com", server: "1.1.1.1", queryType: .a,
                                    records: [DNSRecord(name: "a.com", type: .a, value: "1.2.3.4", ttl: 60)], queryTime: 12)
        #expect(await probes(dns: dns).lookup("a.com") == 12)
    }

    @Test func placeholderSignalValuesAreNoReading() async {
        let wifi = StubWiFi()
        wifi.info = WiFiInfo(ssid: "Home", signalDBm: -100)
        #expect(await probes(wifi: wifi).wifiReading() == nil)
        wifi.info = WiFiInfo(ssid: "Home", signalDBm: -67, noiseLevel: -91)
        #expect(await probes(wifi: wifi).wifiReading() == WiFiReading(rssi: -67, noise: -91))
    }

    @Test func portsThatAnswerAreOpen() async {
        #expect(await probes().openPorts(on: "github.com", among: [80, 443]) == [443])
    }

    @Test func noSpeedTestWhileAnotherRuns() async {
        #expect(await probes(canRunSpeedTest: false).downloadSpeed() == nil)
    }
}
