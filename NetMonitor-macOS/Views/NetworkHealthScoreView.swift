import SwiftUI
import NetMonitorCore

/// macOS dashboard widget showing composite network health score.
struct NetworkHealthScoreView: View {
    @State private var viewModel = NetworkHealthScoreMacViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Network Health", systemImage: "heart.text.square")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCalculating)
                .accessibilityIdentifier("healthScore_button_refresh")
            }

            if viewModel.isCalculating {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Calculating…").font(.caption).foregroundStyle(MacTheme.Colors.labelSecondary)
                }
            } else if let score = viewModel.currentScore {
                HStack(spacing: 16) {
                    // Circular score
                    ZStack {
                        Circle()
                            .stroke(MacTheme.Colors.hairline, lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: CGFloat(score.score) / 100.0)
                            .stroke(gradeColor(score.score), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.5), value: score.score)
                        VStack(spacing: 1) {
                            Text("\(score.score)")
                                .font(.title3).fontWeight(.bold)
                            Text(score.grade)
                                .font(.caption2).foregroundStyle(gradeColor(score.score))
                        }
                    }
                    .frame(width: 60, height: 60)
                    .accessibilityIdentifier("healthScore_label_gauge")

                    // Details
                    VStack(alignment: .leading, spacing: 4) {
                        if let ms = score.latencyMs {
                            macScoreRow(label: "Latency", value: String(format: "%.0f ms", ms))
                        }
                        if let loss = score.packetLoss {
                            macScoreRow(label: "Packet Loss", value: String(format: "%.0f%%", loss * 100))
                        }
                        if let dns = score.details["dns"] {
                            macScoreRow(label: "DNS", value: dns)
                        }
                    }
                }
            } else {
                Text("Click refresh to calculate")
                    .font(.caption)
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
            }
        }
        .macGlassCard()
        .accessibilityIdentifier("dashboard_card_healthScore")
        .task { await viewModel.refresh() }
    }

    private func gradeColor(_ score: Int) -> Color {
        MacTheme.Colors.healthScoreColor(score)
    }

    private func macScoreRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(MacTheme.Colors.labelSecondary)
            Spacer()
            Text(value).font(.caption).fontDesign(.monospaced)
        }
    }
}

// MARK: - macOS ViewModel

@MainActor
@Observable
final class NetworkHealthScoreMacViewModel {
    var currentScore: NetworkHealthScore?
    var isCalculating: Bool = false
    /// Pass/warn checklist shown in the Health Checks card (#397).
    private(set) var checks: [HealthCheck] = []
    /// Per-server DNS timings from the last comparison (#399).
    private(set) var dnsResults: [DNSBenchmarkResult] = []
    private(set) var isComparingDNS = false
    /// The network the last refresh scored, whose history the chart shows.
    private(set) var historyNetworkID: UUID?

    private let service: NetworkHealthScoreService
    private let pingService: any PingServiceProtocol
    private let vpnService: any VPNDetectionServiceProtocol
    private let readDNSServers: @Sendable () -> HealthCheckInputs.DNSServers
    private let dnsBenchmark: DNSServerBenchmark
    private let historyStore: HealthScoreHistoryStore

    init(
        service: NetworkHealthScoreService = NetworkHealthScoreService(),
        pingService: any PingServiceProtocol = PingService(),
        vpnService: any VPNDetectionServiceProtocol = VPNDetectionService(),
        readDNSServers: @escaping @Sendable () -> HealthCheckInputs.DNSServers = { SystemDNSConfiguration.current() },
        dnsBenchmark: DNSServerBenchmark = DNSServerBenchmark(),
        historyStore: HealthScoreHistoryStore = .shared
    ) {
        self.service = service
        self.pingService = pingService
        self.vpnService = vpnService
        self.readDNSServers = readDNSServers
        self.dnsBenchmark = dnsBenchmark
        self.historyStore = historyStore
    }

    var fastestDNS: DNSBenchmarkResult? { DNSServerBenchmark.fastest(dnsResults) }

    /// The scored network's saved scores, oldest first (#491 D10). Read through the store, so it
    /// updates when the 15-minute sampler records too.
    var history: [HealthScoreSample] {
        historyNetworkID.map(historyStore.samples(for:)) ?? []
    }

    /// The history chart needs a line: at least two samples.
    var showsHistoryChart: Bool { history.count >= 2 }

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

    /// Recalculates the score and checklist. When `gatewayIP` is given the router is
    /// pinged too; `localInputs` carries Wi-Fi and device readings the view already has.
    /// `networkProfileID` is the Mac's own network while connected to it: the score is saved to
    /// its history (#491).
    func refresh(
        gatewayIP: String? = nil,
        localInputs: HealthCheckInputs = HealthCheckInputs(),
        networkProfileID: UUID? = nil
    ) async {
        vpnService.startMonitoring()
        isCalculating = true
        defer { isCalculating = false }
        historyNetworkID = networkProfileID

        var latencyMs: Double? = nil
        var packetLoss: Double? = nil

        let stream = await pingService.ping(host: "8.8.8.8", count: 5, timeout: 3)
        var results: [PingResult] = []
        for await result in stream { results.append(result) }

        if !results.isEmpty {
            let ok = results.filter { !$0.isTimeout }
            latencyMs = ok.isEmpty ? nil : ok.map(\.time).reduce(0, +) / Double(ok.count)
            packetLoss = Double(results.count - ok.count) / Double(results.count)
        }

        service.update(
            latencyMs: latencyMs, packetLoss: packetLoss, dnsResponseMs: nil,
            deviceCount: nil, typicalDeviceCount: nil, isConnected: true
        )
        let score = await service.calculateScore()
        currentScore = score
        // Saved at once: at most one sample per 15 minutes, so nothing waits for quit. A refresh
        // cancelled mid-probe (a new scan restarts it) scored partial pings: not saved, or the
        // throttle would turn away the full reading that follows.
        if !Task.isCancelled, let networkProfileID, historyStore.record(score, networkProfileID: networkProfileID) {
            historyStore.flush()
        }

        var inputs = localInputs
        if let gatewayIP {
            var gatewayAnswered = false
            for await result in await pingService.ping(host: gatewayIP, count: 2, timeout: 2) where !result.isTimeout {
                gatewayAnswered = true
            }
            inputs.gatewayReachable = gatewayAnswered
        }
        inputs.internetReachable = results.isEmpty ? nil : latencyMs != nil
        inputs.dnsServers = readDNSServers()
        inputs.vpnActive = vpnService.status.isActive
        checks = NetworkHealthChecklist.evaluate(inputs)
    }
}

#Preview {
    NetworkHealthScoreView()
        .frame(width: 280)
        .padding()
}
