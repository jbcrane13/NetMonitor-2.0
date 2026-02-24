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

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func ping(host: String, maxNodes: Int) async -> AsyncStream<WorldPingLocationResult> {
        AsyncStream { continuation in
            Task {
                do {
                    let (requestId, nodes) = try await self.submitCheck(host: host, maxNodes: maxNodes)
                    let results = try await self.pollResults(requestId: requestId, nodes: nodes)
                    for result in results {
                        continuation.yield(result)
                    }
                } catch {
                    logger.error("World ping failed: \(error.localizedDescription)")
                    continuation.yield(WorldPingLocationResult(
                        id: "error",
                        country: "Error",
                        city: error.localizedDescription,
                        latencyMs: nil,
                        isSuccess: false
                    ))
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

        // nodes dict: key → [country, city, region, countryCode, ip]
        let nodes = response.nodes.reduce(into: [String: NodeMeta]()) { acc, pair in
            let arr = pair.value
            acc[pair.key] = NodeMeta(
                country: arr.count > 0 ? arr[0] : "Unknown",
                city: arr.count > 1 ? arr[1] : pair.key,
                countryCode: arr.count > 3 ? arr[3] : ""
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
            guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

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
            let meta = nodes[nodeKey]

            if let pings = value as? [[Any]], let first = pings.first {
                let status = first.first as? String ?? ""
                // Latency from API is in seconds; convert to ms
                let latencyMs: Double? = first.count > 1 ? (first[1] as? Double).map { $0 * 1000 } : nil
                results.append(WorldPingLocationResult(
                    id: nodeKey,
                    country: meta?.country ?? "Unknown",
                    city: meta?.city ?? nodeKey,
                    latencyMs: latencyMs,
                    isSuccess: status == "OK"
                ))
            } else {
                results.append(WorldPingLocationResult(
                    id: nodeKey,
                    country: meta?.country ?? "Unknown",
                    city: meta?.city ?? nodeKey,
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
