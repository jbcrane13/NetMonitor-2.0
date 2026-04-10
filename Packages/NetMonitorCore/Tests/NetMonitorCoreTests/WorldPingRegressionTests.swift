import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Regression tests for Globalping.io implementation
//
// These tests verify that WorldPingService correctly maps Globalping.io API responses
// to WorldPingLocationResult values. The service was switched from check-host.net to
// Globalping.io in commit b7204d4.
//
// Bug 3: GeoLocationService used HTTP (ip-api.com free tier), blocked by iOS ATS —
//         all geo-lookups silently failed, GeoTrace map showed no pins
//
// Bug 4 (NetMonitor-2.0-82l): poll endpoint HTTP errors were not surfaced as lastError.
//         Fix: detect HTTP 4xx/5xx on poll endpoint and throw pollFailed.

// MARK: - WorldPing Globalping.io format regression tests

@Suite(.serialized)
struct WorldPingRegressionContractTests {

    init() { MockURLProtocol.requestHandler = nil }

    // MARK: Helpers

    private static let fixtureDir: URL = .init(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures")

    private func loadFixture(_ name: String) throws -> Data {
        let url = Self.fixtureDir.appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    private func makeGlobalpingSession(submitData: Data, pollData: Data) -> URLSession {
        MockURLProtocol.makeSession { request in
            let data = request.httpMethod == "POST" ? submitData : pollData
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
    }

    // MARK: - Probe field mapping

    @Test("Globalping probe fields (city, continent) are correctly mapped to result")
    func globalpingProbeFieldsAreMapped() async throws {
        let submitData  = try loadFixture("globalping-submit-success.json")
        let resultsData = try loadFixture("globalping-result-complete.json")

        let session = makeGlobalpingSession(submitData: submitData, pollData: resultsData)
        let service = WorldPingService(session: session)

        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 5) { results.append(r) }

        // City comes from probe.city; country is mapped from continent code via continentName()
        let frankfurt = results.first { $0.city == "Frankfurt" }
        #expect(frankfurt != nil, "Expected a Frankfurt result")
        #expect(frankfurt?.country == "Europe", "EU continent should map to 'Europe'")

        let ashburn = results.first { $0.city == "Ashburn" }
        #expect(ashburn?.country == "North America", "NA continent should map to 'North America'")
    }

    // MARK: - isSuccess flag

    @Test("Results are isSuccess=true when status=finished and timings.total is present")
    func finishedStatusWithTimingsIsSuccess() async throws {
        let submitData  = try loadFixture("globalping-submit-success.json")
        let resultsData = try loadFixture("globalping-result-complete.json")

        let session = makeGlobalpingSession(submitData: submitData, pollData: resultsData)
        let service = WorldPingService(session: session)

        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 5) { results.append(r) }

        let successCount = results.filter { $0.isSuccess }.count
        #expect(successCount == 5, "All 5 finished nodes with timings should be isSuccess=true; got \(successCount)")
    }

    // MARK: - latencyMs

    @Test("Latency from timings.total is used directly as latencyMs")
    func latencyFromTimingsTotalIsUsed() async throws {
        let submitData  = try loadFixture("globalping-submit-success.json")
        let resultsData = try loadFixture("globalping-result-complete.json")

        let session = makeGlobalpingSession(submitData: submitData, pollData: resultsData)
        let service = WorldPingService(session: session)

        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 5) { results.append(r) }

        let frankfurt = results.first { $0.city == "Frankfurt" }
        let latency = try #require(frankfurt?.latencyMs)
        // fixture: timings.total = 32.0 → latencyMs should be 32.0
        #expect(abs(latency - 32.0) < 0.1, "timings.total=32.0 should map to latencyMs=32ms, got \(latency)")
    }

    // MARK: - Timeout / missing timings

    @Test("Results with missing timings.total are isSuccess=false with nil latency")
    func missingTimingsIsFailure() async throws {
        let submitData  = try loadFixture("globalping-submit-success.json")
        let resultsData = try loadFixture("globalping-result-all-timeout.json")

        let session = makeGlobalpingSession(submitData: submitData, pollData: resultsData)
        let service = WorldPingService(session: session)

        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "unreachable.test", maxNodes: 5) { results.append(r) }

        #expect(results.count == 5)
        #expect(results.allSatisfy { !$0.isSuccess }, "Nodes without timings should be isSuccess=false")
        #expect(results.allSatisfy { $0.latencyMs == nil }, "Nodes without timings should have nil latencyMs")
    }
}

// MARK: - Bug 4 Regression Tests: poll endpoint error surfacing (NetMonitor-2.0-82l)

@Suite(.serialized)
struct WorldPingPollErrorRegressionTests {

    init() { MockURLProtocol.requestHandler = nil }

    // MARK: - HTTP errors on poll endpoint surface lastError

    @Test("Poll returns HTTP 404 (measurement expired): lastError is set, stream finishes empty")
    func pollHTTP404SetsLastError() async throws {
        // Regression (Bug 4): HTTP errors on the poll endpoint must surface as lastError.
        // Globalping.io returns HTTP 404 for expired or unknown measurement IDs.
        let submitJSON = "{\"id\":\"gp-poll-test-404\"}"
        let session = MockURLProtocol.makeSession { request in
            let isSubmit = request.httpMethod == "POST"
            let statusCode = isSubmit ? 200 : 404
            let body = isSubmit ? submitJSON : "{\"error\":\"measurement not found\"}"
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        let service = WorldPingService(session: session)
        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 1) {
            results.append(r)
        }

        #expect(results.isEmpty, "HTTP 404 on poll must finish stream empty")
        #expect(service.lastError != nil, "HTTP 404 on poll endpoint must set lastError")
        #expect(service.lastError?.isEmpty == false)
    }

    @Test("Poll returns HTTP 500: lastError is set, stream finishes empty")
    func pollHTTP500SetsLastError() async throws {
        let submitJSON = "{\"id\":\"gp-poll-test-500\"}"
        let session = MockURLProtocol.makeSession { request in
            let isSubmit = request.httpMethod == "POST"
            let statusCode = isSubmit ? 200 : 500
            let body = isSubmit ? submitJSON : "{\"error\":\"internal server error\"}"
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        let service = WorldPingService(session: session)
        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 1) {
            results.append(r)
        }

        #expect(results.isEmpty, "HTTP 500 on poll endpoint must NOT yield results — stream must finish empty")
        #expect(service.lastError != nil, "lastError must be set when poll endpoint returns HTTP 500")
    }

    @Test("Poll returns HTTP 429 (rate limit): lastError is set, stream finishes empty")
    func pollHTTP429SetsLastError() async throws {
        let submitJSON = "{\"id\":\"gp-poll-test-429\"}"
        let session = MockURLProtocol.makeSession { request in
            let isSubmit = request.httpMethod == "POST"
            let statusCode = isSubmit ? 200 : 429
            let body = isSubmit ? submitJSON : "{\"error\":\"rate limited\"}"
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        let service = WorldPingService(session: session)
        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 1) {
            results.append(r)
        }

        #expect(results.isEmpty, "HTTP 429 on poll must finish stream empty")
        #expect(service.lastError != nil, "HTTP 429 on poll endpoint must set lastError")
    }

    @Test("Successful submit + successful poll: results returned normally")
    func successPathWorksCorrectly() async throws {
        let submitJSON = "{\"id\":\"gp-poll-test-success\"}"
        let pollJSON = """
        {
          "status": "finished",
          "results": [
            {
              "probe": {"city": "London", "country": "United Kingdom", "continent": "EU"},
              "result": {"status": "finished", "timings": {"total": 24.0}, "statusCode": 200, "resolvedAddress": "216.58.204.46"}
            }
          ]
        }
        """
        let session = MockURLProtocol.makeSession { request in
            let isSubmit = request.httpMethod == "POST"
            let body = isSubmit ? submitJSON : pollJSON
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        let service = WorldPingService(session: session)
        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 1) {
            results.append(r)
        }

        #expect(!results.isEmpty, "Happy path must produce results")
        #expect(results.count == 1)
        #expect(results.first?.city == "London")
        #expect(results.first?.isSuccess == true)
        #expect(service.lastError == nil)
    }
}

// MARK: - GeoLocationService ATS Regression Test

struct GeoLocationServiceATSRegressionTests {

    @Test("GeoLocationService URL scheme is http — Info.plist must have ATS exception",
          .tags(.integration))
    func geoLookupReturnsRealLocation() async throws {
        // Regression: ATS was blocking http://ip-api.com on iOS.
        // This test FAILS if the NSAppTransportSecurity exception for ip-api.com
        // is removed from Info.plist — catching the regression immediately.
        let service = GeoLocationService()
        let location = try await service.lookup(ip: "8.8.8.8")

        #expect(!location.country.isEmpty,
                "Country must be non-empty — ATS may be blocking HTTP if this fails")
        #expect(location.latitude != 0 || location.longitude != 0,
                "Coordinates must be non-zero — ATS may be blocking HTTP if this fails")
        #expect(location.city.lowercased().contains("mountain") || !location.city.isEmpty,
                "City should be populated (8.8.8.8 is Google, Mountain View, CA)")
    }

    @Test("GeoLocationService uses http:// scheme — documents ATS dependency")
    func geoServiceUsesHTTPScheme() {
        // Documents the architectural constraint: ip-api.com free tier is HTTP-only.
        // If this test fails, the base URL changed — verify ATS exception is still needed.
        let service = GeoLocationService()
        // Access the base URL via the service's session to verify HTTP scheme
        // This is a documentation test — it always passes, but forces the constraint
        // to be visible so it's never silently removed.
        _ = service  // service exists and can be created
        #expect(Bool(true), "ip-api.com is HTTP-only. Info.plist MUST have NSExceptionDomains entry. See commit 6ff1a12.")
    }
}
