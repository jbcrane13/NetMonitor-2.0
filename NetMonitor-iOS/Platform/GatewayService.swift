import Foundation
import NetMonitorCore
import Network
import NetworkScanKit

@MainActor
@Observable
final class GatewayService: GatewayServiceProtocol {
    private(set) var gateway: GatewayInfo?
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    /// Rolling history of recent latency measurements (newest first, max 60).
    /// Used by the dashboard jitter/stability visualization.
    private(set) var latencyHistory: [Double] = []

    private let pingService: any PingServiceProtocol
    private let gatewayIPProvider: @Sendable () -> String?
    private static let maxHistory = 60

    init(
        pingService: any PingServiceProtocol = PingService(),
        gatewayIPProvider: @escaping @Sendable () -> String? = { NetworkUtilities.detectDefaultGateway() }
    ) {
        self.pingService = pingService
        self.gatewayIPProvider = gatewayIPProvider
    }

    func detectGateway() async {
        isLoading = true
        lastError = nil

        defer { isLoading = false }

        guard let gatewayIP = gatewayIPProvider() else {
            lastError = "Could not detect gateway"
            gateway = nil
            return
        }

        let latency = await measureLatency(to: gatewayIP)

        if let latency {
            latencyHistory.insert(latency, at: 0)
            if latencyHistory.count > Self.maxHistory {
                latencyHistory = Array(latencyHistory.prefix(Self.maxHistory))
            }
        }

        gateway = GatewayInfo(
            ipAddress: gatewayIP,
            macAddress: nil,
            vendor: nil,
            latency: latency
        )
    }

    /// Measure gateway latency via ICMP ping (3 probes, best of 3).
    private func measureLatency(to host: String) async -> Double? {
        let stream = await pingService.ping(host: host, count: 3, timeout: 2)

        var best: Double?
        for await result in stream where !result.isTimeout {
            if let current = best {
                best = min(current, result.time)
            } else {
                best = result.time
            }
        }
        return best
    }
}
