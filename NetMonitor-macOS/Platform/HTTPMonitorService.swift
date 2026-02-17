import Foundation

/// Actor-based HTTP/HTTPS monitoring service
actor HTTPMonitorService: NetworkMonitorService {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpMaximumConnectionsPerHost = 1
        config.httpShouldUsePipelining = false
        self.session = URLSession(configuration: config)
    }

    func check(request: TargetCheckRequest) async throws -> MeasurementResult {
        guard request.targetProtocol == .http || request.targetProtocol == .https else {
            throw NetworkMonitorError.invalidHost("Target protocol must be HTTP or HTTPS")
        }

        let scheme = request.targetProtocol == .https ? "https" : "http"
        let port = request.port.map { ":\($0)" } ?? ""
        guard let url = URL(string: "\(scheme)://\(request.host)\(port)") else {
            throw NetworkMonitorError.invalidHost(request.host)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = request.timeout
        urlRequest.httpMethod = "HEAD"
        urlRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let startTime = Date()

        do {
            let (_, response) = try await session.data(for: urlRequest)
            let latency = Date().timeIntervalSince(startTime) * 1000

            if let httpResponse = response as? HTTPURLResponse {
                let isReachable = (200...399).contains(httpResponse.statusCode)
                return MeasurementResult(
                    targetID: request.id,
                    timestamp: Date(),
                    latency: latency,
                    isReachable: isReachable,
                    errorMessage: isReachable ? nil : "HTTP \(httpResponse.statusCode)"
                )
            }

            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: latency,
                isReachable: true,
                errorMessage: nil
            )

        } catch let error as URLError {
            let errorMessage: String
            switch error.code {
            case .timedOut: errorMessage = "Request timed out"
            case .notConnectedToInternet, .networkConnectionLost: errorMessage = "Network unreachable"
            default: errorMessage = error.localizedDescription
            }
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: nil,
                isReachable: false,
                errorMessage: errorMessage
            )
        } catch {
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: nil,
                isReachable: false,
                errorMessage: "Unexpected error: \(error.localizedDescription)"
            )
        }
    }
}
