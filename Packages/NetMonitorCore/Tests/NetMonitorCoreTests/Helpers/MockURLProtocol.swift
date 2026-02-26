import Foundation

/// Test-only URLProtocol that intercepts all URLSession requests and routes them
/// to a handler closure. Supports two handler dispatch modes:
///
/// 1. **Per-session handler** (race-free, preferred for new tests): create a session via
///    `makeSession(responses:)` or `makeSession(handler:)`. The handler is stored in
///    `sessionHandlers` keyed by a UUID that the session injects into each request via
///    the `X-Mock-Session-Token` header. Concurrent sessions don't interfere.
///
/// 2. **Global static handler** (shared, legacy): set `requestHandler` directly, or use
///    `stub(json:statusCode:)` / `stubRoutes(_:statusCode:)` + `makeSession()`.
///    Tests using this path must run inside a `.serialized` suite to prevent races.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    // MARK: - Global static handler (legacy, shared across sessions)
    // nonisolated(unsafe): tests set this before creating the session and read it only
    // on the URLProtocol dispatch queue — serialized suites prevent data races.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    // MARK: - Per-session handler registry
    // Key: a UUID string injected into every request as a custom header by the session.
    // Value: handler closure specific to that session.
    // nonisolated(unsafe): access is always serialized by URLSession's internal serial
    // dispatch queue for a given session, and different sessions use different keys.
    nonisolated(unsafe) private static var sessionHandlers:
        [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    private static let sessionTokenHeader = "X-Mock-Session-Token"

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Per-session handler path (race-free): look up by token in request header.
        if let token = request.value(forHTTPHeaderField: MockURLProtocol.sessionTokenHeader),
           let handler = MockURLProtocol.sessionHandlers[token] {
            dispatch(handler: handler)
            return
        }
        // Global static handler path (legacy).
        if let handler = MockURLProtocol.requestHandler {
            dispatch(handler: handler)
            return
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func dispatch(handler: (URLRequest) throws -> (HTTPURLResponse, Data)) {
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    // MARK: - Session factory: per-session handler (race-free)

    /// Creates a URLSession with a per-session response handler.
    /// Safe to use from concurrently-running test suites — does not touch the
    /// global `requestHandler`.
    ///
    /// - Parameter handler: Called for every request made on the returned session.
    /// - Returns: A configured `URLSession` whose requests go to `handler`.
    static func makeSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let token = UUID().uuidString
        sessionHandlers[token] = handler

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = [sessionTokenHeader: token]
        return URLSession(configuration: config)
    }

    /// Creates a URLSession that dispatches requests to different stub responses
    /// based on URL path substring matching. Race-free — does not use the global handler.
    ///
    /// - Parameter responses: Dictionary mapping URL-path substrings to `(statusCode, data)`.
    static func makeSession(responses: [String: (Int, Data)]) -> URLSession {
        makeSession { request in
            let path = request.url?.absoluteString ?? ""
            for (key, value) in responses {
                if path.contains(key) {
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: value.0,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!
                    return (response, value.1)
                }
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
    }

    // MARK: - Session factory: global static handler (legacy)

    /// Creates a URLSession that routes all requests through the global `requestHandler`.
    /// Set `requestHandler` (or call `stub(json:)` / `stubRoutes(_:)`) **before** calling
    /// this method, then pass the returned session to the service under test.
    ///
    /// Tests using this factory must be in a `.serialized` suite with `init()` and
    /// `defer` cleanup of `requestHandler` to avoid races with concurrent test suites.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - Global static handler helpers (legacy)

    /// Stubs every request to return the given JSON string with the given status code.
    /// Sets the global `requestHandler` — use inside `.serialized` suites only.
    static func stub(json: String, statusCode: Int = 200) {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
    }

    /// Routes requests by URL path substring to JSON response strings.
    /// Sets the global `requestHandler` — use inside `.serialized` suites only.
    static func stubRoutes(_ routes: [String: String], statusCode: Int = 200) {
        requestHandler = { request in
            let path = request.url?.absoluteString ?? ""
            let json = routes.first(where: { path.contains($0.key) })?.value ?? "{}"
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
    }

    // MARK: - Fixture loading

    /// Loads a fixture file from the TestFixtures bundle resource directory.
    /// Resources are registered via `resources: [.process("TestFixtures")]` in Package.swift.
    static func loadFixture(named name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
            throw NSError(
                domain: "MockURLProtocol",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Fixture '\(name)' not found in Bundle.module"]
            )
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
