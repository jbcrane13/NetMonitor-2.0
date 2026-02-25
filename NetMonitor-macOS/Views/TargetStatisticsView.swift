import SwiftUI
import NetMonitorCore
import SwiftData
import Charts

struct TargetStatisticsView: View {
    let target: NetworkTarget
    @Environment(\.appAccentColor) private var accentColor

    @Query private var measurements: [TargetMeasurement]

    init(target: NetworkTarget) {
        self.target = target

        // Query last 50 measurements for this target
        let targetID = target.id
        let predicate = #Predicate<TargetMeasurement> { measurement in
            measurement.target?.id == targetID
        }

        _measurements = Query(
            filter: predicate,
            sort: [SortDescriptor(\TargetMeasurement.timestamp, order: .reverse)],
            animation: .default
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Measurements")
                .font(.headline)

            if measurements.isEmpty {
                Text("No measurements yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Statistics
                HStack(spacing: 32) {
                    StatisticItem(
                        title: "Avg Latency",
                        value: averageLatency,
                        unit: "ms"
                    )

                    StatisticItem(
                        title: "Min Latency",
                        value: minLatency,
                        unit: "ms"
                    )

                    StatisticItem(
                        title: "Max Latency",
                        value: maxLatency,
                        unit: "ms"
                    )

                    StatisticItem(
                        title: "Uptime",
                        value: uptime,
                        unit: "%"
                    )
                }

                // Chart
                Chart {
                    ForEach(measurements.prefix(20).reversed()) { measurement in
                        if let latency = measurement.latency {
                            LineMark(
                                x: .value("Time", measurement.timestamp),
                                y: .value("Latency", latency)
                            )
                            .foregroundStyle(accentColor)
                        }
                    }
                }
                .frame(height: 150)
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("target_statistics_card")
    }

    // MARK: - Statistics (extracted to TargetMeasurement model for testability)

    private var statistics: MeasurementStatistics {
        TargetMeasurement.calculateStatistics(from: Array(measurements))
    }

    private var averageLatency: String { statistics.averageLatencyFormatted }
    private var minLatency: String { statistics.minLatencyFormatted }
    private var maxLatency: String { statistics.maxLatencyFormatted }
    private var uptime: String { statistics.uptimeFormatted }
}

struct StatisticItem: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("target_statistics_item_\(title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }
}

#if DEBUG
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: NetworkTarget.self, TargetMeasurement.self,
        configurations: config
    )
    let target = NetworkTarget(name: "Test", host: "1.1.1.1", targetProtocol: .icmp)
    container.mainContext.insert(target)
    return TargetStatisticsView(target: target)
        .modelContainer(container)
        .frame(width: 600)
}
#endif
