import Foundation
import NetMonitorCore

/// Measures the network health score: five pings to 8.8.8.8 fed to `NetworkHealthScoreService`.
/// The dashboard's view model and the background refresh task both use it, so a sample taken in
/// the background is scored the same way as one on screen (#491 D10).
@MainActor
struct HealthSampleProbe {
    /// One measurement.
    struct Reading {
        let score: NetworkHealthScore
        /// Whether 8.8.8.8 answered; nil when no ping result came back at all.
        let internetReachable: Bool?
    }

    private let service: any NetworkHealthScoreServiceProtocol
    private let pingService: any PingServiceProtocol
    private let networkMonitor: any NetworkMonitorServiceProtocol

    init(
        service: any NetworkHealthScoreServiceProtocol = NetworkHealthScoreService(),
        pingService: any PingServiceProtocol = PingService(),
        networkMonitor: any NetworkMonitorServiceProtocol = NetworkMonitorService.shared
    ) {
        self.service = service
        self.pingService = pingService
        self.networkMonitor = networkMonitor
    }

    func measure() async -> Reading {
        var latencyMs: Double?
        var packetLoss: Double?

        let stream = await pingService.ping(host: "8.8.8.8", count: 5, timeout: 3)
        var results: [PingResult] = []
        for await result in stream {
            guard !Task.isCancelled else { break }
            results.append(result)
        }

        if !results.isEmpty {
            let successful = results.filter { !$0.isTimeout }
            latencyMs = successful.isEmpty ? nil : successful.map(\.time).reduce(0, +) / Double(successful.count)
            packetLoss = Double(results.count - successful.count) / Double(results.count)
        }

        service.update(
            latencyMs: latencyMs,
            packetLoss: packetLoss,
            dnsResponseMs: nil,
            deviceCount: nil,
            typicalDeviceCount: nil,
            isConnected: networkMonitor.isConnected
        )
        let score = await service.calculateScore()
        return Reading(score: score, internetReachable: results.isEmpty ? nil : latencyMs != nil)
    }

    /// The network health samples belong to: the one this device is on. Never the active
    /// profile, which can be a remote or manual network the pings from here don't measure.
    static func localNetworkProfileID(in manager: NetworkProfileManager = NetworkProfileManager()) -> UUID? {
        manager.localProfile?.id
    }
}
