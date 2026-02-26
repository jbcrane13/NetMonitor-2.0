import Foundation
import Testing
@testable import NetMonitorCore

/// Tests verifying that WorldPingService properly surfaces errors instead of
/// yielding fake "error" result nodes that mask failures from the ViewModel.
///
/// The fix (Bead NetMonitor-2.0-50j): on error, the service now finishes the
/// stream empty and sets `lastError`, allowing the ViewModel's existing
/// `results.isEmpty` check to correctly trigger `errorMessage`.
@Suite("WorldPingService — Error Surfacing", .serialized)
struct WorldPingServiceErrorTests {

    init() { MockURLProtocol.requestHandler = nil }

    // MARK: - lastError is set on failure

    @Test("lastError is set when submit request fails with HTTP 500")
    func lastErrorSetOnHTTP500() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.stub(json: "{\"error\": \"internal server error\"}", statusCode: 500)

        let service = WorldPingService(session: MockURLProtocol.makeSession())
        var results: [WorldPingLocationResult] = []
        for await result in await service.ping(host: "google.com", maxNodes: 5) {
            results.append(result)
        }

        #expect(service.lastError != nil, "lastError must be set when the API call fails")
        #expect(service.lastError?.isEmpty == false)
    }

    @Test("lastError is set when network is unreachable")
    func lastErrorSetOnNetworkError() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = WorldPingService(session: MockURLProtocol.makeSession())
        var results: [WorldPingLocationResult] = []
        for await result in await service.ping(host: "google.com", maxNodes: 5) {
            results.append(result)
        }

        #expect(service.lastError != nil, "lastError must be set on network failure")
    }

    @Test("lastError is set when DNS resolution fails")
    func lastErrorSetOnDNSFailure() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotFindHost)
        }

        let service = WorldPingService(session: MockURLProtocol.makeSession())
        var results: [WorldPingLocationResult] = []
        for await result in await service.ping(host: "nonexistent.invalid", maxNodes: 5) {
            results.append(result)
        }

        #expect(service.lastError != nil)
    }

    // MARK: - Stream finishes empty on error (no fake results)

    @Test("Error does NOT yield a fake result — stream finishes empty")
    func errorYieldsNoFakeResult() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = WorldPingService(session: MockURLProtocol.makeSession())
        var results: [WorldPingLocationResult] = []
        for await result in await service.ping(host: "google.com", maxNodes: 5) {
            results.append(result)
        }

        #expect(results.isEmpty,
                "Error must NOT yield a fake result with country='Error' — stream should finish empty")
    }

    @Test("No result with id='error' or country='Error' is yielded on failure")
    func noSyntheticErrorNode() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        MockURLProtocol.stub(json: "invalid json that cannot be decoded", statusCode: 200)

        let service = WorldPingService(session: MockURLProtocol.makeSession())
        var results: [WorldPingLocationResult] = []
        for await result in await service.ping(host: "google.com", maxNodes: 5) {
            results.append(result)
        }

        let errorNodes = results.filter { $0.id == "error" || $0.country == "Error" }
        #expect(errorNodes.isEmpty,
                "No synthetic error node should be yielded — the ViewModel handles errors via results.isEmpty")
    }

    // MARK: - lastError is cleared on new ping

    @Test("lastError is cleared when a new ping starts")
    func lastErrorClearedOnNewPing() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        let service = WorldPingService(session: MockURLProtocol.makeSession())

        // First call: trigger an error
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        for await _ in await service.ping(host: "fail.test", maxNodes: 1) {}
        #expect(service.lastError != nil, "Precondition: lastError should be set after failure")

        // Second call: succeed (use fixture-style stubs)
        let submitJSON = """
        {"ok":1,"request_id":"test123","nodes":{"n1.node.check-host.net":["us","United States","Ashburn","1.2.3.4","AS1234"]}}
        """
        let resultJSON = """
        {"n1.node.check-host.net":[[["OK",0.025]]]}
        """
        MockURLProtocol.stubRoutes([
            "check-ping": submitJSON,
            "check-result": resultJSON
        ])

        // Start the new ping — lastError should be nil immediately
        let stream = await service.ping(host: "google.com", maxNodes: 1)
        // Consume stream
        for await _ in stream {}

        #expect(service.lastError == nil, "lastError should be cleared when a new ping starts successfully")
    }

    // MARK: - Successful ping does not set lastError

    @Test("Successful ping leaves lastError as nil")
    func successfulPingNoLastError() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        let submitJSON = """
        {"ok":1,"request_id":"abc","nodes":{"de1.node.check-host.net":["de","Germany","Frankfurt","5.6.7.8","AS5678"]}}
        """
        let resultJSON = """
        {"de1.node.check-host.net":[[["OK",0.032]]]}
        """
        MockURLProtocol.stubRoutes([
            "check-ping": submitJSON,
            "check-result": resultJSON
        ])

        let service = WorldPingService(session: MockURLProtocol.makeSession())
        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 1) {
            results.append(r)
        }

        #expect(service.lastError == nil, "lastError should remain nil on successful ping")
        #expect(!results.isEmpty, "Results should be populated on success")
    }
}
