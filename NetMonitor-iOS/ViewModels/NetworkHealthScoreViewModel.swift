import Foundation
import NetMonitorCore

/// ViewModel for the Network Health Score dashboard card.
@MainActor
@Observable
final class NetworkHealthScoreViewModel {

    // MARK: - State

    var currentScore: NetworkHealthScore?
    var isCalculating: Bool = false
    var lastUpdated: Date?
    var errorMessage: String?
    /// Pass/warn checklist shown under the score (#397).
    private(set) var checks: [HealthCheck] = []
    /// Per-server DNS timings from the last comparison (#399).
    private(set) var dnsResults: [DNSBenchmarkResult] = []
    private(set) var isComparingDNS = false

    // MARK: - Dependencies

    private let service: any NetworkHealthScoreServiceProtocol
    private let pingService: any PingServiceProtocol
    private let networkMonitor: any NetworkMonitorServiceProtocol
    private let vpnService: any VPNDetectionServiceProtocol
    private let readDNSServers: @Sendable () -> HealthCheckInputs.DNSServers
    private let dnsBenchmark: DNSServerBenchmark
    private var currentTask: Task<Void, Never>?

    init(
        service: any NetworkHealthScoreServiceProtocol = NetworkHealthScoreService(),
        pingService: any PingServiceProtocol = PingService(),
        networkMonitor: any NetworkMonitorServiceProtocol = NetworkMonitorService(),
        vpnService: any VPNDetectionServiceProtocol = VPNDetectionService(),
        readDNSServers: @escaping @Sendable () -> HealthCheckInputs.DNSServers = { SystemDNSConfiguration.current() },
        dnsBenchmark: DNSServerBenchmark = DNSServerBenchmark()
    ) {
        self.service = service
        self.pingService = pingService
        self.networkMonitor = networkMonitor
        self.vpnService = vpnService
        self.readDNSServers = readDNSServers
        self.dnsBenchmark = dnsBenchmark
    }

    // MARK: - Computed

    var gradeText: String { currentScore?.grade ?? "—" }
    var scoreValue: Int { currentScore?.score ?? 0 }

    var latencyText: String {
        guard let ms = currentScore?.latencyMs else { return "—" }
        return String(format: "%.0f ms", ms)
    }

    var packetLossText: String {
        guard let loss = currentScore?.packetLoss else { return "—" }
        return String(format: "%.0f%%", loss * 100)
    }

    var fastestDNS: DNSBenchmarkResult? { DNSServerBenchmark.fastest(dnsResults) }

    // MARK: - Actions

    /// Recalculates the score and checklist. `localInputs` carries what the dashboard
    /// already measured (router, Wi-Fi, device count); the rest is measured here.
    func refresh(localInputs: HealthCheckInputs = HealthCheckInputs()) {
        guard !isCalculating else { return }
        currentTask?.cancel()
        currentTask = Task { await performRefresh(localInputs: localInputs) }
    }

    /// Times lookups against the current DNS server and Cloudflare, Google and Quad9.
    func compareDNSServers() async {
        guard !isComparingDNS else { return }
        isComparingDNS = true
        defer { isComparingDNS = false }
        var current: [String]?
        if case let .servers(addresses) = readDNSServers() {
            current = addresses
        }
        let servers = DNSServerBenchmark.servers(currentNameservers: current)
        dnsResults = await dnsBenchmark.run(servers: servers)
    }

    // periphery:ignore
    func startAutoRefresh(interval: TimeInterval = 60) {
        currentTask?.cancel()
        currentTask = Task {
            while !Task.isCancelled {
                await performRefresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    // periphery:ignore
    func stopAutoRefresh() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Private

    private func performRefresh(localInputs: HealthCheckInputs = HealthCheckInputs()) async {
        vpnService.startMonitoring()
        isCalculating = true
        errorMessage = nil
        defer { isCalculating = false }

        var latencyMs: Double? = nil
        var packetLoss: Double? = nil

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
        currentScore = score
        lastUpdated = Date()

        var inputs = localInputs
        inputs.internetReachable = results.isEmpty ? nil : latencyMs != nil
        inputs.dnsServers = readDNSServers()
        inputs.vpnActive = vpnService.status.isActive
        checks = NetworkHealthChecklist.evaluate(inputs)

        NetworkEventService.shared.log(
            type: .toolRun,
            title: "Health Score: \(score.grade) (\(score.score))",
            details: score.details["latency"].map { "Latency: \($0)" },
            severity: score.score >= 70 ? .success : (score.score >= 40 ? .warning : .error)
        )
    }
}
