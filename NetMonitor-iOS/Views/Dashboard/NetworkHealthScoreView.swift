import SwiftUI
import NetMonitorCore

/// Dashboard card showing the composite network health score.
struct NetworkHealthScoreView: View {
    @State private var viewModel = NetworkHealthScoreViewModel()

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                // Header
                HStack {
                    Image(systemName: "heart.text.square")
                        .foregroundStyle(Theme.Colors.error)
                    Text("Network Health")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    GlassIconButton(icon: "arrow.clockwise", size: 32) {
                        viewModel.refresh()
                    }
                    .disabled(viewModel.isCalculating)
                    .accessibilityIdentifier("healthScore_button_refresh")
                }

                if viewModel.isCalculating {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                        Text("Calculating…")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else if let score = viewModel.currentScore {
                    HStack(spacing: Theme.Layout.sectionSpacing) {
                        // Circular gauge
                        ScoreGauge(score: score.score, grade: score.grade)
                            .frame(width: 90, height: 90)
                            .accessibilityIdentifier("healthScore_label_gauge")

                        // Breakdown
                        VStack(alignment: .leading, spacing: 6) {
                            if let latencyMs = score.latencyMs {
                                ScoreRow(label: "Latency", value: String(format: "%.0f ms", latencyMs), icon: "arrow.up.arrow.down")
                            }
                            if let loss = score.packetLoss {
                                ScoreRow(label: "Packet Loss", value: String(format: "%.0f%%", loss * 100), icon: "exclamationmark.triangle")
                            }
                            if let dns = score.details["dns"] {
                                ScoreRow(label: "DNS", value: dns, icon: "globe")
                            }
                        }
                    }
                } else {
                    emptyState
                }

                if let updated = viewModel.lastUpdated {
                    Text("Updated \(updated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard_card_healthScore")
        .task {
            viewModel.refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.text.square")
                .font(.title2)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("Tap refresh to calculate score")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Score Gauge

private struct ScoreGauge: View {
    let score: Int
    let grade: String

    private var gaugeColor: Color {
        switch score {
        case 80...100: return Theme.Colors.success
        case 60..<80:  return Theme.Colors.warning
        case 40..<60:  return Color.orange
        default:       return Theme.Colors.error
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.glassBorder, lineWidth: 6)

            Circle()
                .trim(from: 0, to: CGFloat(score) / 100.0)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [gaugeColor.opacity(0.6), gaugeColor]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: score)

            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(grade)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(gaugeColor)
            }
        }
    }
}

// MARK: - Score Row

private struct ScoreRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 14)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fontDesign(.monospaced)
        }
    }
}

#Preview {
    NetworkHealthScoreView()
        .padding()
        .themedBackground()
}
