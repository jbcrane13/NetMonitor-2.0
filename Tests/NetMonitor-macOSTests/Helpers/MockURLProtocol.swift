import Foundation

/// Test-only URLProtocol for macOS unit tests. Intercepts URLSession requests and
/// routes them to a per-session handler closure. Uses a UUID token to isolate
/// concurrent test suites from one another.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    private static let store = HandlerStore()

    private final class HandlerStore: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

        func set(_ h: @escaping (URLRequest) throws -> (HTTPURLResponse, Data), for token: String) {
            lock.lock()
            defer { lock.unlock() }
            handlers[token] = h
        }

        func get(for token: String) -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
            lock.lock()
            defer { lock.unlock() }
            return handlers[token]
        }
    }

    private static let tokenHeader = "X-Mock-Session-Token"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let token = request.value(forHTTPHeaderField: MockURLProtocol.tokenHeader),
              let handler = MockURLProtocol.store.get(for: token) else {
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

    /// Creates a URLSession whose requests are handled by `handler`. Safe to use
    /// from concurrent test suites — does not touch any shared global state.
    static func makeSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let token = UUID().uuidString
        store.set(handler, for: token)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = [tokenHeader: token]
        return URLSession(configuration: config)
    }
}
