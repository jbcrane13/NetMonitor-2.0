import Foundation

/// Test-only URLProtocol that intercepts all URLSession requests and routes them
/// to a static handler closure. Allows contract tests to exercise the real
/// URLSession + real Decoder pipeline with controlled fixture data.
///
/// Usage:
/// ```swift
/// MockURLProtocol.requestHandler = { request in
///     let response = HTTPURLResponse(url: request.url!, statusCode: 200, ...)!
///     return (response, Data(json.utf8))
/// }
/// let session = MockURLProtocol.makeSession()
/// // use session in service init
/// ```
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    // nonisolated(unsafe) is appropriate here: tests set this before creating the
    // session and read it only on the URLProtocol dispatch queue — no data races
    // in practice for sequential unit tests.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    // MARK: - Helpers

    /// Creates a URLSession that routes all requests through MockURLProtocol.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Stubs every request to return the given JSON string with the given status code.
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

    /// Stubs requests by routing different URLs to different JSON responses.
    /// `routes` is a dictionary mapping a URL path substring to a JSON string.
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
