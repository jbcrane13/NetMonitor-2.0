import Foundation
import os.log

/// Pings a target from multiple global locations using the Globalping.io API.
///
/// API flow:
/// 1. POST https://api.globalping.io/v1/measurements  →  measurement ID
/// 2. Poll GET https://api.globalping.io/v1/measurements/{id} until status == "finished"
/// 3. Yield one `WorldPingLocationResult` per probe
///
/// Free tier: 100 measurements/hour, no API key required.
/// Probes span 6 continents with ~600 nodes worldwide.
public final class WorldPingService: WorldPingServiceProtocol, @unchecked Sendable {
    private let session: URLSession
    private let baseURL = "https://api.globalping.io/v1"
    private let logger = Logger(subsystem: "com.netmonitor", category: "WorldPingService")

    /// Set after a ping attempt fails. Cleared at the start of each new ping.
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
                    let measurementId = try await self.submitMeasurement(host: host, limit: maxNodes)
                    let results = try await self.pollResults(measurementId: measurementId)
                    logger.info("World ping got \(results.count) results")
                    for result in results {
                        continuation.yield(result)
                    }
                } catch {
                    self.logger.error("World ping failed: \(error.localizedDescription)")
                    self.lastError = error.localizedDescription
                }
                continuation.finish()
            }
        }
    }

    // MARK: - API Calls

    /// Submit a ping measurement to Globalping.
    /// Distributes probes across all 6 continents for global coverage.
    private func submitMeasurement(host: String, limit: Int) async throws -> String {
        guard let url = URL(string: "\(baseURL)/measurements") else {
            throw URLError(.badURL)
        }

        // Distribute probes across continents for meaningful global coverage.
        let continents = ["NA", "EU", "AS", "SA", "OC", "AF"]
        let locations = continents.map { code in
            ["continent": code] as [String: Any]
        }

        let body: [String: Any] = [
            "type": "ping",
            "target": host,
            "locations": locations,
            "measurementOptions": [
                "packets": 3
            ],
            "limit": limit
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("NetMonitor/2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await session.data(for: request)

        if let http = httpResponse as? HTTPURLResponse, http.statusCode >= 400 {
            let apiMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String }
                ?? "HTTP \(http.statusCode)"
            throw GlobalpingError.submitFailed(message: apiMessage)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let measurementId = json["id"] as? String else {
            throw GlobalpingError.submitFailed(message: "Invalid response — no measurement ID")
        }

        logger.info("World ping submitted: measurementId=\(measurementId)")
        return measurementId
    }

    /// Poll the measurement endpoint until all probes finish.
    private func pollResults(measurementId: String, maxAttempts: Int = 15) async throws -> [WorldPingLocationResult] {
        guard let url = URL(string: "\(baseURL)/measurements/\(measurementId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { break }

            let (data, httpResponse) = try await session.data(for: request)

            if let http = httpResponse as? HTTPURLResponse, http.statusCode >= 400 {
                throw GlobalpingError.pollFailed(statusCode: http.statusCode)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                continue
            }

            if status == "finished" || attempt == maxAttempts - 1 {
                return parseResults(json: json)
            }
            // "in-progress" — keep polling
        }
        return []
    }

    // MARK: - Response Parsing

    private func parseResults(json: [String: Any]) -> [WorldPingLocationResult] {
        guard let results = json["results"] as? [[String: Any]] else { return [] }

        return results.compactMap { entry -> WorldPingLocationResult? in
            guard let probe = entry["probe"] as? [String: Any],
                  let result = entry["result"] as? [String: Any] else { return nil }

            let city = probe["city"] as? String ?? "Unknown"
            let country = probe["country"] as? String ?? "??"
            let continent = probe["continent"] as? String ?? ""

            let stats = result["stats"] as? [String: Any]
            let avg = stats?["avg"] as? Double
            let min = stats?["min"] as? Double
            let packetLoss = stats?["loss"] as? Double ?? 0

            // Globalping returns latency in milliseconds already (not seconds)
            let isSuccess = (result["status"] as? String) == "finished" && packetLoss < 100

            // Use continent + country for a richer display name
            let displayCountry = Self.continentName(continent) ?? country

            return WorldPingLocationResult(
                id: "\(city)-\(country)",
                country: displayCountry,
                city: city,
                latencyMs: avg ?? min,
                isSuccess: isSuccess
            )
        }.sorted { $0.city < $1.city }
    }

    // MARK: - Helpers

    private static func continentName(_ code: String) -> String? {
        switch code {
        case "NA": return "North America"
        case "EU": return "Europe"
        case "AS": return "Asia"
        case "SA": return "South America"
        case "OC": return "Oceania"
        case "AF": return "Africa"
        default: return nil
        }
    }

    // MARK: - Errors

    private enum GlobalpingError: LocalizedError {
        case submitFailed(message: String)
        case pollFailed(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .submitFailed(let message):
                return "World ping submit error: \(message)"
            case .pollFailed(let code):
                return "World ping result endpoint returned HTTP \(code)"
            }
        }
    }
}
