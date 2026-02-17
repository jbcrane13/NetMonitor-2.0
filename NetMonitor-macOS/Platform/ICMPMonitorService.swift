import Foundation
import NetMonitorCore

/// Actor-based ICMP ping monitoring service.
/// Uses NetMonitorCore's PingService (ICMP/TCP) for compatibility with App Sandbox.
actor ICMPMonitorService: NetworkMonitorService {

    private let pingService = PingService()

    func check(request: TargetCheckRequest) async throws -> MeasurementResult {
        guard request.targetProtocol == .icmp else {
            throw NetworkMonitorError.invalidHost("Target protocol must be ICMP")
        }

        let stream = await pingService.ping(host: request.host, count: 1, timeout: request.timeout)

        var lastResult: PingResult?
        for await result in stream {
            lastResult = result
        }

        if let result = lastResult {
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: result.isTimeout ? nil : result.time,
                isReachable: !result.isTimeout,
                errorMessage: result.isTimeout ? "Host unreachable (timeout)" : nil
            )
        } else {
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: nil,
                isReachable: false,
                errorMessage: "No ping response received"
            )
        }
    }
}
