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
                    Text("Calculating…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let score = viewModel.currentScore {
                HStack(spacing: 16) {
                    // Circular score
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 5)
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
                    .foregroundStyle(.secondary)
            }
        }
        .macGlassCard()
        .accessibilityIdentifier("dashboard_card_healthScore")
        .task { await viewModel.refresh() }
    }

    private func gradeColor(_ score: Int) -> Color {
        MacTheme.Colors.healthScoreColor(score)
    }

    @ViewBuilder
    private func macScoreRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
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

    private let service: NetworkHealthScoreService
    private let pingService: any PingServiceProtocol

    init(
        service: NetworkHealthScoreService = NetworkHealthScoreService(),
        pingService: any PingServiceProtocol = PingService()
    ) {
        self.service = service
        self.pingService = pingService
    }

    func refresh() async {
        isCalculating = true
        defer { isCalculating = false }

        var latencyMs: Double? = nil
        var packetLoss: Double? = nil

        let stream = await pingService.ping(host: "8.8.8.8", count: 5, timeout: 3)
        var results: [PingResult] = []
// swiftlint:disable:next identifier_name
        for await r in stream { results.append(r) }

        if !results.isEmpty {
            let ok = results.filter { !$0.isTimeout }
            latencyMs = ok.isEmpty ? nil : ok.map(\.time).reduce(0, +) / Double(ok.count)
            packetLoss = Double(results.count - ok.count) / Double(results.count)
        }

        service.update(
            latencyMs: latencyMs, packetLoss: packetLoss, dnsResponseMs: nil,
            deviceCount: nil, typicalDeviceCount: nil, isConnected: true
        )
        currentScore = await service.calculateScore()
    }
}

#Preview {
    NetworkHealthScoreView()
        .frame(width: 280)
        .padding()
}
