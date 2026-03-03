import SwiftUI
import NetMonitorCore

/// Row A (right): Compact circular health gauge for the dashboard no-scroll layout.
struct HealthGaugeCard: View {
    @State private var viewModel = NetworkHealthScoreMacViewModel()

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            // Widget label — pinned to top
            HStack {
                Circle().fill(MacTheme.Colors.success).frame(width: 5, height: 5)
                Text("NETWORK HEALTH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
            }

            // Circular gauge
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: scoreProgress)
                    .stroke(
                        AngularGradient(
                            colors: [MacTheme.Colors.success, MacTheme.Colors.info, MacTheme.Colors.info],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: MacTheme.Colors.info.opacity(0.4), radius: 4)
                    .animation(.easeInOut(duration: 0.5), value: scoreProgress)

                VStack(spacing: 1) {
                    Text(scoreText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("dashboard_healthGauge_score")
                    Text(gradeLabel)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(gradeColor)
                        .tracking(1.0)
                }
            }
            .frame(width: 85, height: 85)

            // Score breakdown bars
            if let score = viewModel.currentScore {
                VStack(spacing: 3) {
                    scoreBar(label: "Latency",  pct: latencyPct(score), color: MacTheme.Colors.success)
                    scoreBar(label: "Loss",     pct: lossPct(score),    color: MacTheme.Colors.success)
                    scoreBar(label: "Devices",  pct: 0.88,              color: MacTheme.Colors.warning)
                }
            } else if viewModel.isCalculating {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .macGlassCard(cornerRadius: 14, padding: 10)
        .clipped()
        .accessibilityIdentifier("dashboard_card_healthGauge")
        .task { await viewModel.refresh() }
    }

    // MARK: Computed

    private var scoreProgress: CGFloat {
        CGFloat(viewModel.currentScore?.score ?? 0) / 100.0
    }

    private var scoreText: String {
        if let s = viewModel.currentScore { return "\(s.score)" }
        return viewModel.isCalculating ? "…" : "—"
    }

    private var gradeText: String {
        viewModel.currentScore?.grade ?? "CALCULATING"
    }

    private var gradeLabel: String {
        guard let score = viewModel.currentScore?.score else { return "···" }
        switch score {
        case 90...100: return "EXCELLENT"
        case 75..<90:  return "GOOD"
        case 50..<75:  return "FAIR"
        default:       return "POOR"
        }
    }

    private var gradeColor: Color {
        guard let score = viewModel.currentScore?.score else { return .secondary }
        switch score {
        case 90...100: return MacTheme.Colors.success
        case 75..<90:  return MacTheme.Colors.info
        case 50..<75:  return MacTheme.Colors.warning
        default:       return MacTheme.Colors.error
        }
    }

    private func latencyPct(_ score: NetworkHealthScore) -> Double {
        guard let ms = score.latencyMs else { return 0 }
        return ms < 10 ? 1.0 : ms < 50 ? 0.85 : ms < 100 ? 0.6 : 0.3
    }

    private func lossPct(_ score: NetworkHealthScore) -> Double {
        guard let loss = score.packetLoss else { return 0 }
        return 1.0 - loss
    }

    // MARK: Sub-view

    @ViewBuilder
    private func scoreBar(label: String, pct: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .frame(width: 46, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(color)
                        .frame(width: g.size.width * CGFloat(min(1, max(0, pct))))
                        .animation(.easeOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 3)
            Text(String(format: "%.0f%%", pct * 100))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26, alignment: .trailing)
        }
    }
}
