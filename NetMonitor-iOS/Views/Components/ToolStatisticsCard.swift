import SwiftUI
import NetMonitorCore

/// A single statistic with label, value, and optional icon
struct ToolStatistic: Identifiable {
    var id: String { label }
    let label: String
    let value: String
    var icon: String? = nil
    var valueColor: Color = Theme.Colors.textPrimary
}

/// A card displaying statistics for network tools (min/max/avg, packet counts, etc.)
struct ToolStatisticsCard: View {
    let title: String
    var icon: String? = nil
    let statistics: [ToolStatistic]
    var columns: Int = 3

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    if let icon {
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(Theme.Colors.accent)
                    }

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer()
                }

                // Statistics Grid
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(statistics) { stat in
                        StatisticItem(statistic: stat)
                    }
                }
            }
        }
        .accessibilityIdentifier("toolStats_card_\(title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }
}

/// A single statistic item in the grid
private struct StatisticItem: View {
    let statistic: ToolStatistic

    var body: some View {
        VStack(spacing: 4) {
            if let icon = statistic.icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(statistic.valueColor)
            }

            Text(statistic.value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(statistic.valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(statistic.label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("toolStats_item_\(statistic.label.lowercased().replacingOccurrences(of: " ", with: "_"))")
        .accessibilityLabel("\(statistic.label): \(statistic.value)")
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.Gradients.background
            .ignoresSafeArea()

        VStack(spacing: 16) {
            ToolStatisticsCard(
                title: "Ping Statistics",
                icon: "chart.bar",
                statistics: [
                    ToolStatistic(label: "Min", value: "10 ms", valueColor: Theme.Colors.success),
                    ToolStatistic(label: "Avg", value: "25 ms"),
                    ToolStatistic(label: "Max", value: "45 ms", valueColor: Theme.Colors.warning)
                ]
            )

            ToolStatisticsCard(
                title: "Packet Statistics",
                icon: "arrow.up.arrow.down",
                statistics: [
                    ToolStatistic(label: "Sent", value: "100", icon: "arrow.up"),
                    ToolStatistic(label: "Received", value: "98", icon: "arrow.down"),
                    ToolStatistic(label: "Lost", value: "2%", icon: "xmark", valueColor: Theme.Colors.error)
                ]
            )

            ToolStatisticsCard(
                title: "Port Scan Results",
                statistics: [
                    ToolStatistic(label: "Open", value: "5", valueColor: Theme.Colors.success),
                    ToolStatistic(label: "Closed", value: "95", valueColor: Theme.Colors.error)
                ],
                columns: 2
            )
        }
        .padding()
    }
}
