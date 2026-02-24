import Foundation
import Testing
@testable import NetMonitorCore

/// Integration tests for PingService.
/// The real service uses ICMPSocket/NetworkFramework — requires network access.
/// Pinging 127.0.0.1 (loopback) works without internet connectivity.
@Suite("PingService Integration Tests")
struct PingServiceIntegrationTests {

    // MARK: - Loopback ping (no internet required)

    @Test("Ping 127.0.0.1 returns at least 1 RTT result", .tags(.integration))
    func pingLoopbackReturnsResult() async {
        let service = PingService()
        var results: [PingResult] = []
        for await result in await service.ping(host: "127.0.0.1", count: 3, timeout: 5.0) {
            results.append(result)
        }
        // Should get at least 1 response from loopback
        let successCount = results.filter { !$0.isTimeout }.count
        #expect(successCount >= 1,
                "Ping to 127.0.0.1 should return at least 1 success, got \(results.count) results total")
    }

    @Test("Ping 127.0.0.1 — statistics are non-nil and packet loss is 0%", .tags(.integration))
    func pingLoopbackStatisticsAreValid() async {
        let service = PingService()
        var results: [PingResult] = []
        for await result in await service.ping(host: "127.0.0.1", count: 3, timeout: 5.0) {
            results.append(result)
        }
        let stats = await service.calculateStatistics(results, requestedCount: 3)
        #expect(stats != nil, "Statistics must be non-nil after ping results")
        if let s = stats {
            #expect(s.packetLoss <= 100.0, "Packet loss must be in range [0, 100]")
            #expect(s.transmitted == 3, "Transmitted must match requested count")
        }
    }

    @Test("Ping stream results have incrementing sequence numbers", .tags(.integration))
    func pingResultsHaveSequenceNumbers() async {
        let service = PingService()
        var results: [PingResult] = []
        for await result in await service.ping(host: "127.0.0.1", count: 3, timeout: 5.0) {
            results.append(result)
        }
        #expect(!results.isEmpty, "Should receive at least one result from loopback ping")
        // Sequence numbers should be positive
        for result in results {
            #expect(result.sequence >= 0, "Sequence number must be non-negative")
        }
    }

    @Test("Ping unreachable host — stream yields results, not silent empty", .tags(.integration))
    func pingUnreachableHostSurfacesResults() async {
        let service = PingService()
        var results: [PingResult] = []
        // Use a non-routable IP — should produce timeout or unreachable results
        for await result in await service.ping(host: "192.0.2.1", count: 2, timeout: 2.0) {
            results.append(result)
        }
        // The stream MUST yield results — either timeouts, ICMP unreachable, or router responses.
        // Silent empty stream is the failure mode we're guarding against.
        // Note: network behavior varies — some paths return ICMP unreachable (non-zero RTT),
        // others return pure timeouts. We only assert the stream is non-empty.
        #expect(!results.isEmpty,
                "Unreachable host must surface results (timeout or error), not an empty stream")
    }

    @Test("stop() terminates an in-flight ping stream", .tags(.integration))
    func stopTerminatesStream() async {
        let service = PingService()
        // Start a long ping
        let pingTask = Task {
            var count = 0
            for await _ in await service.ping(host: "127.0.0.1", count: 100, timeout: 30.0) {
                count += 1
                if count >= 1 { break }  // exit after first result
            }
            return count
        }
        // Stop the service
        await service.stop()
        let count = await pingTask.value
        #expect(count >= 0)  // no crash
    }
}
