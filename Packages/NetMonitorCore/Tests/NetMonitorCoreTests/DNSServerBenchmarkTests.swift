import Testing
import Foundation
@testable import NetMonitorCore

/// Records lookups and returns scripted timings per server address.
private final class FakeDNSLookup: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String: Int] = [:]
    private let timings: [String: [Double?]]

    init(timings: [String: [Double?]]) {
        self.timings = timings
    }

    func callCount(for server: String) -> Int {
        lock.withLock { calls[server] ?? 0 }
    }

    var lookup: DNSServerBenchmark.Lookup {
        { [self] _, server, _ in
            let index: Int = lock.withLock {
                let current = calls[server] ?? 0
                calls[server] = current + 1
                return current
            }
            let scripted = timings[server] ?? []
            return index < scripted.count ? scripted[index] : nil
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set(_ newValue: Bool) { lock.withLock { stored = newValue } }
}

@Suite("DNSServerBenchmark")
struct DNSServerBenchmarkTests {

    private let servers = [
        DNSBenchmarkServer(name: "Your DNS", address: "192.168.1.1"),
        DNSBenchmarkServer.cloudflare,
        DNSBenchmarkServer.google
    ]

    @Test func reportsMedianPerServerInInputOrder() async {
        let fake = FakeDNSLookup(timings: [
            "192.168.1.1": [5, 7, 6, 9, 4, 8, 6, 5, 7],
            "1.1.1.1": [20, 22, 21, 25, 19, 30, 21, 20, 22],
            "8.8.8.8": [40, 41, 39, 42, 38, 40, 41, 39, 40]
        ])
        let benchmark = DNSServerBenchmark(lookup: fake.lookup)
        let results = await benchmark.run(servers: servers)

        #expect(results.map(\.server.address) == ["192.168.1.1", "1.1.1.1", "8.8.8.8"])
        #expect(results[0].medianMs == 6)
        #expect(results[1].medianMs == 21)
        #expect(results[2].medianMs == 40)
        #expect(results.allSatisfy { $0.attempts == 9 && $0.successes == 9 })
        #expect(DNSServerBenchmark.fastest(results)?.server.address == "192.168.1.1")
    }

    @Test func deadServerStopsAfterFirstRoundAndNeverWins() async {
        let fake = FakeDNSLookup(timings: [
            "192.168.1.1": [],
            "1.1.1.1": [12, 14, 13, 12, 14, 13, 12, 14, 13]
        ])
        let benchmark = DNSServerBenchmark(lookup: fake.lookup)
        let results = await benchmark.run(servers: Array(servers.prefix(2)))

        #expect(fake.callCount(for: "192.168.1.1") == DNSServerBenchmark.defaultDomains.count)
        #expect(results[0].medianMs == nil)
        #expect(results[0].successes == 0)
        #expect(DNSServerBenchmark.fastest(results)?.server.address == "1.1.1.1")
    }

    @Test func medianUsesSuccessesOnly() async {
        let fake = FakeDNSLookup(timings: ["1.1.1.1": [10, nil, 30, nil, 20, nil]])
        let benchmark = DNSServerBenchmark(domains: ["a.com", "b.com"], tries: 3, lookup: fake.lookup)
        let results = await benchmark.run(servers: [.cloudflare])
        #expect(results[0].successes == 3)
        #expect(results[0].attempts == 6)
        #expect(results[0].medianMs == 20)
    }

    @Test func allServersFailingHasNoFastest() async {
        let benchmark = DNSServerBenchmark(lookup: FakeDNSLookup(timings: [:]).lookup)
        let results = await benchmark.run(servers: servers)
        #expect(results.allSatisfy { $0.medianMs == nil })
        #expect(DNSServerBenchmark.fastest(results) == nil)
    }

    @Test func serversRunConcurrently() async {
        // Quad9 is listed first and blocks until Cloudflare has answered. Run one server
        // at a time, Cloudflare would never be asked and Quad9 would see zero calls.
        let fake = FakeDNSLookup(timings: ["1.1.1.1": [10]])
        let sawCloudflare = LockedFlag()
        let benchmark = DNSServerBenchmark(domains: ["a.com"], tries: 1) { domain, server, timeout in
            guard server == "9.9.9.9" else { return await fake.lookup(domain, server, timeout) }
            for _ in 0..<200 where fake.callCount(for: "1.1.1.1") == 0 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            sawCloudflare.set(fake.callCount(for: "1.1.1.1") > 0)
            return nil
        }
        let results = await benchmark.run(servers: [.quad9, .cloudflare])
        #expect(sawCloudflare.value)
        #expect(results.map(\.medianMs) == [nil, 10])
    }

    @Test func medianOfEvenCountAveragesMiddlePair() {
        #expect(DNSServerBenchmark.median([4, 1, 3, 2]) == 2.5)
        #expect(DNSServerBenchmark.median([]) == nil)
    }

    @Test func serverListPrependsCurrentServerOnce() {
        let list = DNSServerBenchmark.servers(currentNameservers: ["192.168.1.1", "8.8.8.8"])
        #expect(list.map(\.address) == ["192.168.1.1", "1.1.1.1", "8.8.8.8", "9.9.9.9"])
    }

    @Test func serverListSkipsCurrentServerWhenItIsPublic() {
        #expect(DNSServerBenchmark.servers(currentNameservers: ["1.1.1.1"]).count == 3)
        #expect(DNSServerBenchmark.servers(currentNameservers: nil).count == 3)
    }
}
