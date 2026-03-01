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
        logger.info("World ping starting for host: \(host), maxNodes: \(maxNodes)")
        return AsyncStream { continuation in
            Task {
                do {
                    let (requestId, nodes) = try await self.submitCheck(host: host, maxNodes: maxNodes)
                    let results = try await self.pollResults(requestId: requestId, nodes: nodes)
                    logger.info("World ping got \(results.count) results")
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

        let (data, httpResponse) = try await session.data(for: request)

        // Surface HTTP-level errors immediately with a useful message
        if let http = httpResponse as? HTTPURLResponse, http.statusCode >= 400 {
            // Try to extract an API-level error message from the body before throwing
            let apiMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? String ?? $0["message"] as? String }
            throw WorldPingError.submitHTTPError(
                statusCode: http.statusCode,
                apiMessage: apiMessage
            )
        }

        // If the API returns ok=0 the response body may be a plain error dict rather than
        // a valid CheckPingResponse. Try decoding as the expected type; if that fails, extract
        // any error message from the raw JSON to surface a meaningful error instead of a
        // generic DecodingError.
        do {
            let response = try JSONDecoder().decode(CheckPingResponse.self, from: data)
            guard response.ok == 1 else {
                // ok=0 means the API rejected the request (e.g. invalid host, rate limit)
                throw WorldPingError.submitAPIError(message: "API returned ok=\(response.ok) for host '\(host)'")
            }
            // nodes dict: key → [countryCode, country, city, ip, asn]
            // e.g. "at1.node.check-host.net": ["at", "Austria", "Vienna", "185.224.3.111", "AS64457"]
            let nodes = response.nodes.reduce(into: [String: NodeMeta]()) { acc, pair in
                let arr = pair.value
                acc[pair.key] = NodeMeta(
                    country: arr.count > 1 ? arr[1] : "Unknown",
                    city: arr.count > 2 ? arr[2] : pair.key,
                    countryCode: arr.isEmpty ? "" : arr[0]
                )
            }
            logger.info("World ping submitted: requestId=\(response.requestId), nodes=\(nodes.count)")
            return (response.requestId, nodes)
        } catch let error as WorldPingError {
            throw error
        } catch {
            // Decoding failed — extract API error message from raw JSON if available
            let rawError = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? String ?? $0["message"] as? String }
            if let msg = rawError {
                throw WorldPingError.submitAPIError(message: msg)
            }
            logger.error("submitCheck decode error: \(error)")
            throw error
        }
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

        var anyValidPollResponse = false

        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled else { break }

            let (data, response) = try await session.data(for: request)

            // Surface HTTP errors — a 4xx/5xx on the result endpoint means the
            // request ID is invalid or the service is down. Don't silently retry.
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 400 {
                throw WorldPingError.pollHTTPError(statusCode: httpResponse.statusCode)
            }

            guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.warning("pollResults: failed to parse JSON response on attempt \(attempt) — retrying")
                continue
            }

            anyValidPollResponse = true

            // Guard: if the response contains no keys from our submitted node set,
            // the API returned an error document (e.g. {"error": "..."}) rather than
            // probe results. Surface this as a real error instead of silently returning [].
            let hasAnyNodeKey = raw.keys.contains { nodes[$0] != nil }
            if !hasAnyNodeKey && !nodes.isEmpty {
                // Decode the API error message if present, otherwise use a generic description
                let apiError = raw["error"] as? String
                    ?? raw["message"] as? String
                    ?? "unexpected response (got keys: \(Array(raw.keys).sorted()))"
                throw WorldPingError.pollAPIError(message: apiError)
            }

            // Wait until all submitted nodes have responded (non-null) or max attempts reached
            let allReady = raw.values.allSatisfy { !($0 is NSNull) }
            if allReady || attempt == maxAttempts - 1 {
                return parseResults(raw: raw, nodes: nodes)
            }
        }

        // If we never received a parseable JSON response from the poll endpoint,
        // surface this as an explicit error rather than returning empty results.
        if !anyValidPollResponse {
            throw WorldPingError.pollUnparseable(attempts: maxAttempts)
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

    /// Errors surfaced via `lastError` to allow the ViewModel to display a meaningful
    /// message instead of a blank screen.
    private enum WorldPingError: LocalizedError {
        case submitHTTPError(statusCode: Int, apiMessage: String?)
        case submitAPIError(message: String)
        case pollHTTPError(statusCode: Int)
        case pollAPIError(message: String)
        case pollUnparseable(attempts: Int)

        var errorDescription: String? {
            switch self {
            case .submitHTTPError(let code, let msg):
                if let apiMsg = msg { return "World ping submit error: \(apiMsg) (HTTP \(code))" }
                return "World ping submit endpoint returned HTTP \(code)"
            case .submitAPIError(let message):
                return "World ping API error: \(message)"
            case .pollHTTPError(let code):
                return "World ping result endpoint returned HTTP \(code)"
            case .pollAPIError(let message):
                return "World ping API error: \(message)"
            case .pollUnparseable(let attempts):
                return "World ping result endpoint returned unparseable responses after \(attempts) attempts"
            }
        }
    }
}
