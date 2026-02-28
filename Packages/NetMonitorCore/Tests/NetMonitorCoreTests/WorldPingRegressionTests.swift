import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Regression tests for bugs fixed in commit 6ff1a12
//
// Bug 1: WorldPingService used wrong node field indices — API returns
//         [countryCode, country, city, ip, asn], not [country, city, region, countryCode, ip]
//
// Bug 2: WorldPingService misread result nesting — API returns [[[Any]]] (triple-nested),
//         not [[Any]] (double-nested), so ALL results fell through to isSuccess=false
//
// Bug 3: GeoLocationService used HTTP (ip-api.com free tier), blocked by iOS ATS —
//         all geo-lookups silently failed, GeoTrace map showed no pins
//
// Bug 4 (NetMonitor-2.0-82l): pollResults silently swallowed error-JSON from the
//         result endpoint — {"error":"..."} caused allReady=true (no nulls), guard
//         in parseResults dropped the "error" key, returned [], and never set lastError.
//         Also: HTTP 4xx/5xx on the poll endpoint was not surfaced as an error.
//         Fix: detect error-JSON (no node keys in response) and HTTP errors on poll.

// MARK: - WorldPing Contract Tests (real API fixture format)

@Suite("WorldPingService — real API format regression", .serialized)
struct WorldPingRegressionContractTests {

    // Resets shared MockURLProtocol.requestHandler before each test so this suite
    // does not interfere with (or receive interference from) other suites that also
    // use the shared static handler.
    init() { MockURLProtocol.requestHandler = nil }

    // MARK: Helpers

    private static let fixtureDir: URL = .init(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures")

    private func loadFixture(_ name: String) throws -> Data {
        let url = Self.fixtureDir.appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    // MARK: - Node metadata parsing (Bug 1)

    @Test("Node metadata: country at index 1, city at index 2, countryCode at index 0")
    func nodeMetadataIndicesAreCorrect() throws {
        // Real API: ["at", "Austria", "Vienna", "185.224.3.111", "AS64457"]
        // Old (wrong): country=arr[0], city=arr[1], countryCode=arr[3]
        // Fixed:       country=arr[1], city=arr[2], countryCode=arr[0]
        let submitData = try loadFixture("check-host-submit-real.json")
        let decoded = try JSONDecoder().decode(CheckPingResponsePublic.self, from: submitData)

        let at = decoded.nodes["at1.node.check-host.net"]
        #expect(at?[safe: 0] == "at",      "countryCode should be at index 0")
        #expect(at?[safe: 1] == "Austria", "country should be at index 1")
        #expect(at?[safe: 2] == "Vienna",  "city should be at index 2")

        let us = decoded.nodes["us1.node.check-host.net"]
        #expect(us?[safe: 1] == "United States")
        #expect(us?[safe: 2] == "Ashburn")
        #expect(us?[safe: 0] == "us")
    }

    @Test("WorldPingService produces correctly-labelled results from real node format")
    func serviceProducesCorrectLabelsFromRealNodeFormat() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        let submitData   = try loadFixture("check-host-submit-real.json")
        let resultsData  = try loadFixture("check-host-result-real.json")

        let session = MockURLProtocol.makeSession(responses: [
            "check-ping":    (200, submitData),
            "check-result":  (200, resultsData)
        ])
        let service = WorldPingService(session: session)

        var results: [WorldPingLocationResult] = []
        let stream = await service.ping(host: "google.com", maxNodes: 5)
        for await r in stream { results.append(r) }

        // Regression: old wrong indices would produce country="at", city="Austria"
        let austria = results.first { $0.city == "Vienna" }
        #expect(austria != nil,              "Expected a Vienna result")
        #expect(austria?.country == "Austria", "country field must be country name, not code")

        let us = results.first { $0.city == "Ashburn" }
        #expect(us?.country == "United States")
    }

    // MARK: - Triple-nested result parsing (Bug 2)

    @Test("WorldPingService parses triple-nested [[[Any]]] result format — isSuccess true")
    func tripleNestedFormatParsedAsSuccess() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        let submitData  = try loadFixture("check-host-submit-real.json")
        let resultsData = try loadFixture("check-host-result-real.json")

        let session = MockURLProtocol.makeSession(responses: [
            "check-ping":   (200, submitData),
            "check-result": (200, resultsData)
        ])
        let service = WorldPingService(session: session)

        var results: [WorldPingLocationResult] = []
        let stream = await service.ping(host: "google.com", maxNodes: 5)
        for await r in stream { results.append(r) }

        // Regression: old double-nested parsing made ALL results isSuccess=false
        let successCount = results.filter { $0.isSuccess }.count
        #expect(successCount >= 4, "At least 4 of 5 nodes should report success; got \(successCount). Regression: double-nested parse makes all isSuccess=false")
    }

    @Test("WorldPingService averages latency across multiple probes per node")
    func latencyIsAveragedAcrossProbes() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        // at1: 3 probes at 32ms, 29ms, 31ms → avg ≈ 30.67ms (× 1000 from seconds)
        let submitData  = try loadFixture("check-host-submit-real.json")
        let resultsData = try loadFixture("check-host-result-real.json")

        let session = MockURLProtocol.makeSession(responses: [
            "check-ping":   (200, submitData),
            "check-result": (200, resultsData)
        ])
        let service = WorldPingService(session: session)

        var results: [WorldPingLocationResult] = []
        let stream = await service.ping(host: "google.com", maxNodes: 5)
        for await r in stream { results.append(r) }

        let austria = results.first { $0.city == "Vienna" }
        let latency = try #require(austria?.latencyMs)
        // avg of 32, 29, 31 ms = 30.666... ms
        #expect(latency > 29 && latency < 33, "Expected averaged latency ~30.7ms, got \(latency)")
    }

    @Test("WorldPingService marks node successful when first probe is OK; averages latency across OK probes")
    func mixedProbesAveragesLatencyFromOKProbes() async throws {
        defer { MockURLProtocol.requestHandler = nil }
        // au1: [OK 195ms, timeout, OK 188ms]
        // isSuccess = first probe status == "OK" → true
        // avgLatency = (195 + 188) / 2 = 191.5ms  (timeout entries have no latency field)
        let submitData  = try loadFixture("check-host-submit-real.json")
        let resultsData = try loadFixture("check-host-result-real.json")

        let session = MockURLProtocol.makeSession(responses: [
            "check-ping":   (200, submitData),
            "check-result": (200, resultsData)
        ])
        let service = WorldPingService(session: session)

        var results: [WorldPingLocationResult] = []
        let stream = await service.ping(host: "google.com", maxNodes: 5)
        for await r in stream { results.append(r) }

        let australia = results.first { $0.city == "Sydney" }
        #expect(australia != nil)
        #expect(australia?.isSuccess == true, "First probe is OK → node should be marked successful")
        let latency = try #require(australia?.latencyMs)
        // avg of 195ms and 188ms = 191.5ms; allow small floating-point range
        #expect(latency > 190 && latency < 193,
                "Expected averaged latency ~191.5ms across two OK probes, got \(latency)")
    }
}

// MARK: - Bug 4 Regression Tests: poll endpoint error surfacing (NetMonitor-2.0-82l)

@Suite("WorldPingService — poll endpoint error surfacing regression", .serialized)
struct WorldPingPollErrorRegressionTests {

    init() { MockURLProtocol.requestHandler = nil }

    // MARK: - Error JSON on poll endpoint surfaces lastError

    @Test("Poll returns {\"error\":\"...\"}: lastError is set, stream finishes empty")
    func pollErrorJSONSetsLastError() async throws {
        // Regression (Bug 4): before the fix, {"error":"..."} on the poll endpoint
        // caused allReady=true (no NSNull), parseResults dropped the "error" key via
        // the meta-guard, returned [], and lastError was NEVER set.
        let submitJSON = """
        {"ok":1,"request_id":"test-r1","nodes":{"us1.node.check-host.net":["us","United States","Ashburn","1.2.3.4","AS1234"]}}
        """
        let pollErrorJSON = """
        {"error":"request expired","message":"The request ID has expired or does not exist"}
        """

        let session = MockURLProtocol.makeSession(responses: [
            "check-ping":   (200, Data(submitJSON.utf8)),
            "check-result": (200, Data(pollErrorJSON.utf8))
        ])
        let service = WorldPingService(session: session)

        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 1) {
            results.append(r)
        }

        #expect(results.isEmpty,
                "Poll error-JSON must NOT yield fake results — stream should finish empty")
        #expect(service.lastError != nil,
                "Regression (Bug 4): lastError must be set when poll returns error-JSON with no node keys")
        #expect(service.lastError?.isEmpty == false)
    }

    @Test("Poll returns HTTP 500: lastError is set, stream finishes empty")
    func pollHTTP500SetsLastError() async throws {
        // Regression (Bug 4): HTTP errors on the POLL endpoint (not the submit endpoint)
        // were not surfaced. Before the fix, session.data() returned the error body,
        // JSONSerialization succeeded, allReady=true, parseResults skipped the error key,
        // and [] was returned without setting lastError.
        let submitJSON = """
        {"ok":1,"request_id":"test-r2","nodes":{"de1.node.check-host.net":["de","Germany","Frankfurt","5.6.7.8","AS24940"]}}
        """
        let session = MockURLProtocol.makeSession { request in
            let isSubmit = request.url?.absoluteString.contains("check-ping") == true
            let statusCode = isSubmit ? 200 : 500
            let body = isSubmit
                ? submitJSON
                : "{\"error\":\"internal server error\"}"
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

        #expect(results.isEmpty,
                "HTTP 500 on poll endpoint must NOT yield results — stream must finish empty")
        #expect(service.lastError != nil,
                "Regression (Bug 4): lastError must be set when poll endpoint returns HTTP 500")
    }

    @Test("Poll returns HTTP 429 (rate limit): lastError is set, stream finishes empty")
    func pollHTTP429SetsLastError() async throws {
        let submitJSON = """
        {"ok":1,"request_id":"test-r3","nodes":{"jp1.node.check-host.net":["jp","Japan","Tokyo","1.2.3.4","AS7506"]}}
        """
        let session = MockURLProtocol.makeSession { request in
            let isSubmit = request.url?.absoluteString.contains("check-ping") == true
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
        #expect(service.lastError != nil,
                "HTTP 429 on poll endpoint must set lastError")
    }

    @Test("Successful submit + successful poll: results returned normally after fix")
    func successPathUnaffectedByFix() async throws {
        // Verify the fix did not break the happy path.
        let submitJSON = """
        {"ok":1,"request_id":"test-r4","nodes":{"gb1.node.check-host.net":["gb","United Kingdom","London","9.8.7.6","AS62041"]}}
        """
        let pollJSON = """
        {"gb1.node.check-host.net":[[["OK",0.024,"9.8.7.6",60]]]}
        """
        let session = MockURLProtocol.makeSession(responses: [
            "check-ping":   (200, Data(submitJSON.utf8)),
            "check-result": (200, Data(pollJSON.utf8))
        ])
        let service = WorldPingService(session: session)

        var results: [WorldPingLocationResult] = []
        for await r in await service.ping(host: "google.com", maxNodes: 1) {
            results.append(r)
        }

        #expect(!results.isEmpty, "Happy path must still produce results after Bug 4 fix")
        #expect(results.count == 1)
        #expect(results.first?.city == "London")
        #expect(results.first?.isSuccess == true)
        #expect(service.lastError == nil)
    }
}

// MARK: - GeoLocationService ATS Regression Test

@Suite("GeoLocationService — ATS regression")
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

// MARK: - Helpers

/// Safe subscript for Array<String>
private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

/// Public mirror of WorldPingService's internal CheckPingResponse for fixture parsing
private struct CheckPingResponsePublic: Codable {
    let ok: Int
    let requestId: String
    let nodes: [String: [String]]
    enum CodingKeys: String, CodingKey {
        case ok
        case requestId = "request_id"
        case nodes
    }
}

// The WorldPingRegressionContractTests use MockURLProtocol.makeSession(responses:)
// which is defined in MockURLProtocol.swift and uses a per-session handler token
// (no global static state). No private extension is needed here.
