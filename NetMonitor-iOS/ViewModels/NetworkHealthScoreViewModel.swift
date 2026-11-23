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
    /// The current network's saved scores, oldest first (#491 D10).
    private(set) var history: [HealthScoreSample] = []

    // MARK: - Dependencies

    private let probe: HealthSampleProbe
    private let historyStore: HealthScoreHistoryStore
    private let currentNetworkProfileID: @MainActor () -> UUID?
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
        dnsBenchmark: DNSServerBenchmark = DNSServerBenchmark(),
        historyStore: HealthScoreHistoryStore = .shared,
        currentNetworkProfileID: @escaping @MainActor () -> UUID? = { nil }
    ) {
        probe = HealthSampleProbe(service: service, pingService: pingService, networkMonitor: networkMonitor)
        self.historyStore = historyStore
        self.currentNetworkProfileID = currentNetworkProfileID
        self.vpnService = vpnService
        self.readDNSServers = readDNSServers
        self.dnsBenchmark = dnsBenchmark
    }

    // MARK: - Computed

    /// What the "Explain" card explains: the finished result on screen (#448).
    var insightRequest: InsightRequest? {
        guard !isCalculating, let currentScore else { return nil }
        return ToolInsightBuilder.healthScore(currentScore, checks: checks)
    }

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

    /// The history chart needs a line: at least two samples.
    var showsHistoryChart: Bool { history.count >= 2 }

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

        let networkID = currentNetworkProfileID()
        loadHistory(networkID)
        let reading = await probe.measure()
        let score = reading.score
        currentScore = score
        lastUpdated = Date()
        // Saved at once: at most one sample per 15 minutes, and iOS may suspend the app any time.
        // A refresh cancelled mid-probe scored partial pings: not saved.
        if !Task.isCancelled, let networkID, historyStore.record(score, networkProfileID: networkID) {
            historyStore.flush()
        }
        loadHistory(networkID)

        var inputs = localInputs
        inputs.internetReachable = reading.internetReachable
        inputs.dnsServers = readDNSServers()
        inputs.vpnActive = vpnService.status.isActive
        checks = NetworkHealthChecklist.evaluate(inputs)
    }

    private func loadHistory(_ networkID: UUID?) {
        history = networkID.map(historyStore.samples(for:)) ?? []
    }
}
