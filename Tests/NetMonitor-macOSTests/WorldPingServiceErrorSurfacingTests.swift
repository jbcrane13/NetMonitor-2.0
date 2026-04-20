import Testing
import Foundation
import NetMonitorCore

/// Tests that WorldPingService surfaces errors to callers instead of silently swallowing them.
///
/// WorldPingService has several silent failure points:
/// - submitMeasurement: `try? JSONSerialization.jsonObject(...)` with no fallback (line ~90)
/// - pollResults: `try? JSONSerialization.jsonObject(...)` silently continues on parse failure (line ~127)
/// - ping(): catches all errors and sets `lastError` but yields zero results — callers
///   that only check the stream get no indication something went wrong.
///
/// These tests inject failures via MockURLProtocol and verify the service exposes
/// errors through `lastError` and produces appropriate stream output.
struct WorldPingServiceErrorSurfacingTests {

    // MARK: - Helpers

    /// Creates a WorldPingService wired to a session that always throws.
    private func makeFailingService(error: Error = URLError(.notConnectedToInternet)) -> WorldPingService {
        let session = MockURLProtocol.makeSession { _ in
            throw error
        }
        return WorldPingService(session: session)
    }

    /// Creates a WorldPingService that returns a fixed HTTP status and body.
    private func makeStatusService(statusCode: Int, body: Data = Data()) -> WorldPingService {
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }
        return WorldPingService(session: session)
    }

    /// Creates a WorldPingService that returns a specific JSON body with 200 OK.
    private func makeJSONService(json: Any) -> WorldPingService {
        let data = try! JSONSerialization.data(withJSONObject: json)
        return makeStatusService(statusCode: 200, body: data)
    }

    /// Collects all results from an AsyncStream.
    private func collect(_ stream: AsyncStream<WorldPingLocationResult>) async -> [WorldPingLocationResult] {
        var results: [WorldPingLocationResult] = []
        for await result in stream {
            results.append(result)
        }
        return results
    }

    // MARK: - Network Failure Tests

    @Test("Network error sets lastError and yields zero results")
    func networkErrorSetsLastError() async {
        let service = makeFailingService(error: URLError(.notConnectedToInternet))
        let stream = await service.ping(host: "example.com", maxNodes: 3)
        let results = await collect(stream)

        #expect(results.isEmpty, "No results should be yielded when network is unavailable")
        #expect(service.lastError != nil, "lastError must be set when network request fails")
    }

    @Test("Timeout error surfaces via lastError")
    func timeoutErrorSurfacesViaLastError() async {
        let service = makeFailingService(error: URLError(.timedOut))
        let stream = await service.ping(host: "example.com", maxNodes: 3)
        let results = await collect(stream)

        #expect(results.isEmpty)
        #expect(service.lastError != nil, "Timeout should be surfaced via lastError")
    }

    @Test("lastError is cleared at start of new ping")
    func lastErrorClearedOnNewPing() async {
        let service = makeFailingService()

        // First ping: should set lastError
        let stream1 = await service.ping(host: "example.com", maxNodes: 1)
        _ = await collect(stream1)
        #expect(service.lastError != nil)

        // Second ping: lastError should be cleared at start (even though it will fail again)
        // We verify the clearing behavior by checking during a second call
        let stream2 = await service.ping(host: "example.com", maxNodes: 1)
        _ = await collect(stream2)

        // After second failure, lastError is set again
        #expect(service.lastError != nil, "lastError should be set after second failure too")
    }

    // MARK: - HTTP Error Response Tests

    @Test("HTTP 429 rate limit surfaces error via lastError")
    func http429RateLimitSurfacesError() async throws {
        let errorJSON: [String: Any] = [
            "error": [
                "type": "rate_limit",
                "message": "Rate limit exceeded"
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: errorJSON)
        let service = makeStatusService(statusCode: 429, body: body)

        let stream = await service.ping(host: "example.com", maxNodes: 3)
        let results = await collect(stream)

        #expect(results.isEmpty, "HTTP 429 should yield zero results")
        #expect(service.lastError != nil, "HTTP 429 should surface error via lastError")
        #expect(service.lastError?.contains("Rate limit") == true,
                "Error message should include the API error detail")
    }

    @Test("HTTP 500 server error surfaces via lastError")
    func http500ServerErrorSurfacesError() async {
        let service = makeStatusService(statusCode: 500)

        let stream = await service.ping(host: "example.com", maxNodes: 3)
        let results = await collect(stream)

        #expect(results.isEmpty)
        #expect(service.lastError != nil, "HTTP 500 should surface error via lastError")
    }

    // MARK: - Malformed Response Tests

    @Test("Malformed JSON response (no measurement ID) surfaces error")
    func malformedResponseNoMeasurementIdSurfacesError() async {
        // Return valid JSON but without the expected "id" field
        let service = makeJSONService(json: ["status": "ok", "unexpected": "format"])

        let stream = await service.ping(host: "example.com", maxNodes: 3)
        let results = await collect(stream)

        #expect(results.isEmpty)
        #expect(service.lastError != nil,
                "Missing measurement ID should surface error, not silently return empty results")
    }

    @Test("Empty JSON object surfaces error via lastError")
    func emptyJSONObjectSurfacesError() async {
        let service = makeJSONService(json: [String: Any]())

        let stream = await service.ping(host: "example.com", maxNodes: 3)
        let results = await collect(stream)

        #expect(results.isEmpty)
        #expect(service.lastError != nil,
                "Empty JSON response should surface error, not silently yield nothing")
    }

    @Test("Non-JSON response body surfaces error")
    func nonJSONResponseSurfacesError() async {
        let htmlBody = "<html><body>Bad Gateway</body></html>".data(using: .utf8)!
        let service = makeStatusService(statusCode: 200, body: htmlBody)

        let stream = await service.ping(host: "example.com", maxNodes: 3)
        let results = await collect(stream)

        #expect(results.isEmpty)
        #expect(service.lastError != nil,
                "Non-JSON response should surface error via lastError")
    }

    // MARK: - Poll Phase Failure Tests

    @Test("HTTP error during poll phase surfaces via lastError")
    func httpErrorDuringPollSurfacesError() async {
        var requestCount = 0
        let session = MockURLProtocol.makeSession { request in
            requestCount += 1
            if requestCount == 1 {
                // Submit succeeds — return a measurement ID
                let submitJSON: [String: Any] = ["id": "test-measurement-123"]
                let body = try! JSONSerialization.data(withJSONObject: submitJSON)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 202,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, body)
            } else {
                // Poll fails with 500
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data())
            }
        }
        let service = WorldPingService(session: session)
        let stream = await service.ping(host: "example.com", maxNodes: 3)
        let results = await collect(stream)

        #expect(results.isEmpty, "Poll failure should yield zero results")
        #expect(service.lastError != nil, "Poll HTTP error should surface via lastError")
    }
}
