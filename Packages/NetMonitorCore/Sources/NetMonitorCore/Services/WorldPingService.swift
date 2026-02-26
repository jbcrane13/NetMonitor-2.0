import Foundation
import os.log

/// Pings a target from multiple global locations using the check-host.net API.
///
/// API flow:
/// 1. GET https://check-host.net/check-ping?host=HOST&max_nodes=N  →  request_id + node metadata
/// 2. Poll GET https://check-host.net/check-result/REQUEST_ID until all nodes respond
/// 3. Yield one `WorldPingLocationResult` per node
public final class WorldPingService: WorldPingServiceProtocol, @unchecked Sendable {
    private let session: URLSession
    private let baseURL = "https://check-host.net"
    private let logger = Logger(subsystem: "com.netmonitor", category: "WorldPingService")

    /// Set after a ping attempt fails. Cleared at the start of each new ping.
    /// The ViewModel can read this to surface a meaningful error message.
    public private(set) var lastError: String?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func ping(host: String, maxNodes: Int) async -> AsyncStream<WorldPingLocationResult> {
        lastError = nil
        return AsyncStream { continuation in
            Task {
                do {
                    let (requestId, nodes) = try await self.submitCheck(host: host, maxNodes: maxNodes)
                    let results = try await self.pollResults(requestId: requestId, nodes: nodes)
                    for result in results {
                        continuation.yield(result)
                    }
                } catch {
                    self.logger.error("World ping failed: \(error.localizedDescription)")
                    self.lastError = error.localizedDescription
                    // Don't yield a fake "error" result — let the stream finish empty
                    // so the ViewModel's `results.isEmpty` check correctly triggers errorMessage.
                }
                continuation.finish()
            }
        }
    }

    // MARK: - API Calls

    private func submitCheck(host: String, maxNodes: Int) async throws -> (String, [String: NodeMeta]) {
        guard var components = URLComponents(string: "\(baseURL)/check-ping") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "max_nodes", value: "\(maxNodes)")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NetMonitor/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(CheckPingResponse.self, from: data)

        // nodes dict: key → [countryCode, country, city, ip, asn]
        // e.g. "at1.node.check-host.net": ["at", "Austria", "Vienna", "185.224.3.111", "AS64457"]
        let nodes = response.nodes.reduce(into: [String: NodeMeta]()) { acc, pair in
            let arr = pair.value
            acc[pair.key] = NodeMeta(
                country: arr.count > 1 ? arr[1] : "Unknown",
                city: arr.count > 2 ? arr[2] : pair.key,
                countryCode: arr.count > 0 ? arr[0] : ""
            )
        }
        return (response.requestId, nodes)
    }

    private func pollResults(
        requestId: String,
        nodes: [String: NodeMeta],
        maxAttempts: Int = 8
    ) async throws -> [WorldPingLocationResult] {
        guard let url = URL(string: "\(baseURL)/check-result/\(requestId)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled else { break }

            let (data, _) = try await session.data(for: request)
            guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.warning("pollResults: failed to parse JSON response on attempt \(attempt) — retrying")
                continue
            }

            // Wait until all nodes have responded (non-null) or max attempts reached
            let allReady = raw.values.allSatisfy { !($0 is NSNull) }
            if allReady || attempt == maxAttempts - 1 {
                return parseResults(raw: raw, nodes: nodes)
            }
        }
        return []
    }

    // MARK: - Response Parsing

    private func parseResults(raw: [String: Any], nodes: [String: NodeMeta]) -> [WorldPingLocationResult] {
        var results: [WorldPingLocationResult] = []

        for (nodeKey, value) in raw {
            guard let meta = nodes[nodeKey] else {
                // Skip keys that don't correspond to a known probe node.
                // Error responses (e.g. {"error": "..."}) or geo-JSON accidentally
                // received on the result endpoint will have keys that aren't in
                // the nodes dictionary — treating them as probe nodes would produce
                // fake results that mask the real error from the ViewModel.
                continue
            }

            // API response structure: [[[status, latency, ip?], [status, latency], ...]]
            // The value is wrapped in an extra array layer: [[[Any]]]
            // Try the triple-nested format first, then fall back to double-nested
            let pingEntries: [[Any]]?
            if let tripleNested = value as? [[[Any]]], let inner = tripleNested.first {
                pingEntries = inner
            } else if let doubleNested = value as? [[Any]] {
                pingEntries = doubleNested
            } else {
                pingEntries = nil
            }

            if let pings = pingEntries, let first = pings.first {
                let status = first.first as? String ?? ""
                // Latency from API is in seconds; convert to ms
                let latencyMs: Double? = first.count > 1 ? (first[1] as? Double).map { $0 * 1000 } : nil

                // Average latency across all pings for this node
                let allLatencies = pings.compactMap { entry -> Double? in
                    guard entry.count > 1 else { return nil }
                    return (entry[1] as? Double).map { $0 * 1000 }
                }
                let avgLatency = allLatencies.isEmpty ? latencyMs : allLatencies.reduce(0, +) / Double(allLatencies.count)

                results.append(WorldPingLocationResult(
                    id: nodeKey,
                    country: meta.country,
                    city: meta.city,
                    latencyMs: avgLatency,
                    isSuccess: status == "OK"
                ))
            } else {
                results.append(WorldPingLocationResult(
                    id: nodeKey,
                    country: meta.country,
                    city: meta.city,
                    latencyMs: nil,
                    isSuccess: false
                ))
            }
        }

        return results.sorted { $0.city < $1.city }
    }

    // MARK: - Private Types

    private struct CheckPingResponse: Codable {
        let ok: Int
        let requestId: String
        let nodes: [String: [String]]

        enum CodingKeys: String, CodingKey {
            case ok
            case requestId = "request_id"
            case nodes
        }
    }

    private struct NodeMeta {
        let country: String
        let city: String
        let countryCode: String
    }
}
