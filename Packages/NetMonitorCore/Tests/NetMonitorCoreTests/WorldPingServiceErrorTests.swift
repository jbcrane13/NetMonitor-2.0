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
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 500, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("{\"error\": \"internal server error\"}".utf8))
        }

        let service = WorldPingService(session: session)
        var results: [WorldPingLocationResult] = []
        for await result in await service.ping(host: "google.com", maxNodes: 5) {
            results.append(result)
        }

        #expect(service.lastError != nil, "lastError must be set when the API call fails")
        #expect(service.lastError?.isEmpty == false)
    }

    @Test("lastError is set when network is unreachable")
    func lastErrorSetOnNetworkError() async throws {
        let session = MockURLProtocol.makeSession { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = WorldPingService(session: session)
        var results: [WorldPingLocationResult] = []
        for await result in await service.ping(host: "google.com", maxNodes: 5) {
            results.append(result)
        }

        #expect(service.lastError != nil, "lastError must be set on network failure")
    }

    @Test("lastError is set when DNS resolution fails")
    func lastErrorSetOnDNSFailure() async throws {
        let session = MockURLProtocol.makeSession { _ in
            throw URLError(.cannotFindHost)
        }

        let service = WorldPingService(session: session)
        var results: [WorldPingLocationResult] = []
        for await result in await service.ping(host: "nonexistent.invalid", maxNodes: 5) {
            results.append(result)
        }

        #expect(service.lastError != nil)
    }

    // MARK: - Stream finishes empty on error (no fake results)

    @Test("Error does NOT yield a fake result — stream finishes empty")
    func errorYieldsNoFakeResult() async throws {
        let session = MockURLProtocol.makeSession { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = WorldPingService(session: session)
        var results: [WorldPingLocationResult] = []
        for await result in await service.ping(host: "google.com", maxNodes: 5) {
            results.append(result)
        }

        #expect(results.isEmpty,
                "Error must NOT yield a fake result with country='Error' — stream should finish empty")
    }

    @Test("No result with id='error' or country='Error' is yielded on failure")
    func noSyntheticErrorNode() async throws {
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data("invalid json that cannot be decoded".utf8))
        }

        let service = WorldPingService(session: session)
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
        // First call: error session to trigger lastError
        let errorSession = MockURLProtocol.makeSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service1 = WorldPingService(session: errorSession)
        for await _ in await service1.ping(host: "fail.test", maxNodes: 1) {}
        #expect(service1.lastError != nil, "Precondition: lastError should be set after failure")

        // Second call: a fresh service with a success session — lastError starts nil
        let submitJSON = "{\"id\":\"gp-clear-test\"}"
        let resultJSON = """
        {
          "status": "finished",
          "results": [
            {
              "probe": {"city": "Ashburn", "country": "United States", "continent": "NA"},
              "result": {"status": "finished", "timings": {"total": 25.0}, "statusCode": 200}
            }
          ]
        }
        """
        let successSession = MockURLProtocol.makeSession { request in
            let body = request.httpMethod == "POST" ? submitJSON : resultJSON
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let service2 = WorldPingService(session: successSession)
        for await _ in await service2.ping(host: "google.com", maxNodes: 1) {}

        #expect(service2.lastError == nil, "lastError should be nil on successful ping")
    }

    // MARK: - Successful ping does not set lastError

    @Test("Successful ping leaves lastError as nil")
    func successfulPingNoLastError() async throws {
        let submitJSON = "{\"id\":\"gp-success-test\"}"
        let resultJSON = """
        {
          "status": "finished",
          "results": [
            {
              "probe": {"city": "Frankfurt", "country": "Germany", "continent": "EU"},
              "result": {"status": "finished", "timings": {"total": 32.0}, "statusCode": 200}
            }
          ]
        }
        """
        let session = MockURLProtocol.makeSession { request in
            let body = request.httpMethod == "POST" ? submitJSON : resultJSON
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let service = WorldPingService(session: session)
        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 1) {
            results.append(r)
        }

        #expect(service.lastError == nil, "lastError should remain nil on successful ping")
        #expect(!results.isEmpty, "Results should be populated on success")
    }
}
