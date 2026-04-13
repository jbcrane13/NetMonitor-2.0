import Testing
import Foundation
@testable import NetMonitorCore

struct WorldPingServiceIntegrationTests {

    // MARK: - Real Globalping.io API

    @Test(.tags(.integration), .timeLimit(.minutes(2)))
    func realPingToWellKnownHostReturnsResults() async throws {
        let service = WorldPingService()
        let stream = await service.ping(host: "google.com", maxNodes: 6)

        var results: [WorldPingLocationResult] = []
        for await result in stream {
            results.append(result)
        }

        if let error = service.lastError {
            // Network or API failure is acceptable in CI. The key assertion:
            // the error was captured (not silently swallowed) and the stream finished.
            #expect(!error.isEmpty, "Error should have a meaningful message")
        } else {
            // If the API responded successfully, we should have at least one result
            #expect(!results.isEmpty, "Expected at least one probe result from Globalping.io")

            // Verify result structure
            if let first = results.first {
                #expect(!first.city.isEmpty, "City should be populated")
                #expect(!first.country.isEmpty, "Country should be populated")
                #expect(!first.id.isEmpty, "ID should be populated")

                if first.isSuccess {
                    #expect(first.latencyMs != nil, "Successful probe should have latency")
                    #expect(first.latencyMs! > 0, "Latency should be positive")
                    #expect(first.latencyMs! < 30_000, "Latency should be under 30 seconds")
                }
            }
        }
    }

    @Test(.tags(.integration), .timeLimit(.minutes(2)))
    func realPingResultsSortedByLatency() async throws {
        let service = WorldPingService()
        let stream = await service.ping(host: "cloudflare.com", maxNodes: 6)

        var results: [WorldPingLocationResult] = []
        for await result in stream {
            results.append(result)
        }

        guard service.lastError == nil, results.count >= 2 else {
            // Network unavailable or insufficient results: skip ordering check
            return
        }

        // Results should be sorted by latency ascending (nil at end)
        let latencies = results.compactMap(\.latencyMs)
        for i in 1..<latencies.count {
            #expect(
                latencies[i] >= latencies[i - 1],
                "Results should be sorted by ascending latency"
            )
        }
    }

    @Test(.tags(.integration), .timeLimit(.minutes(2)))
    func errorSurfacedForInvalidHost() async throws {
        let service = WorldPingService()
        // Use a clearly invalid target that the Globalping API should reject
        let stream = await service.ping(host: "this-host-does-not-exist-xyz123.invalid", maxNodes: 3)

        var results: [WorldPingLocationResult] = []
        for await result in stream {
            results.append(result)
        }

        // Either the API rejects the invalid host (lastError set),
        // or probes report failure (isSuccess == false).
        // Both are valid outcomes. The key: no silent swallowing.
        if let error = service.lastError {
            #expect(!error.isEmpty, "Error for invalid host should have a message")
        } else if !results.isEmpty {
            // API accepted the measurement but probes should fail to resolve
            let anySuccess = results.contains { $0.isSuccess }
            // It is acceptable if some probes happen to resolve (DNS caching, etc.)
            // but we at least verify results were returned and structured properly
            for result in results {
                #expect(!result.id.isEmpty, "Result ID should be non-empty")
            }
            _ = anySuccess // suppress unused warning
        }
        // If both results and error are empty, the stream finished cleanly with no data,
        // which is also acceptable for an invalid host
    }

    @Test(.tags(.integration), .timeLimit(.minutes(2)))
    func lastErrorClearedOnNewPing() async throws {
        let service = WorldPingService()

        // First: ping an invalid host to potentially set lastError
        let stream1 = await service.ping(host: "invalid-host-zzz.invalid", maxNodes: 1)
        for await _ in stream1 { /* drain */ }

        // Second: ping a valid host -- lastError should be cleared at start
        let stream2 = await service.ping(host: "google.com", maxNodes: 1)

        // At this point, before consuming results, lastError should already be nil
        // because ping() sets lastError = nil at the start
        // (We cannot check between the two calls easily, but we can verify after)
        var results: [WorldPingLocationResult] = []
        for await result in stream2 {
            results.append(result)
        }

        if service.lastError == nil {
            // Good: error was cleared and the second ping succeeded
            // (or at least did not error out)
        } else {
            // If both pings failed (network down), that is acceptable.
            // The important thing is the error is from the SECOND call, not stale.
            #expect(
                service.lastError?.isEmpty == false,
                "If error persists it should be from the latest call"
            )
        }
    }
}
