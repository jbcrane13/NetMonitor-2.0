import Foundation
@testable import NetMonitorCore

/// Fake `WHOISTransport` keyed by (server, query) so WHOISService's port-43
/// referral-following fallback can be tested without a real `NWConnection`.
final class FakeWHOISTransport: WHOISTransport, @unchecked Sendable {
    private let responses: [String: String]
    private(set) var queriedServers: [String] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    func query(_ query: String, server: String, port: Int) async throws -> String {
        queriedServers.append(server)
        guard let response = responses[Self.key(server: server, query: query)] else {
            throw NSError(
                domain: "FakeWHOISTransport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "no stub for server=\(server) query=\(query)"]
            )
        }
        return response
    }

    static func key(server: String, query: String) -> String {
        "\(server.lowercased())|\(query.lowercased())"
    }
}
