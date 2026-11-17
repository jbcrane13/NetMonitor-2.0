import Charts
import SwiftUI

/// 7-day trend of saved speed tests (#398): pick download, upload or ping.
public struct SpeedTestTrendChart: View {
    public enum Metric: String, CaseIterable, Identifiable {
        case download = "Download"
        case upload = "Upload"
        case ping = "Ping"

        public var id: String { rawValue }

        var unit: String { self == .ping ? "ms" : "Mbps" }

        func value(_ entry: SpeedTestHistoryEntry) -> Double {
            switch self {
            case .download: entry.downloadMbps
            case .upload: entry.uploadMbps
            case .ping: entry.pingMs
            }
        }
    }

    private let entries: [SpeedTestHistoryEntry]
    private let accessibilityPrefix: String
    @State private var metric: Metric = .download

    /// `entries` should already be limited to 7 days (see `SpeedTestTrend.lastSevenDays`).
    public init(entries: [SpeedTestHistoryEntry], accessibilityPrefix: String) {
        self.entries = entries
        self.accessibilityPrefix = accessibilityPrefix
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last 7 days")
                    .font(.caption.weight(.semibold))
                Spacer()
                Picker("Metric", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
                .accessibilityIdentifier("\(accessibilityPrefix)_picker_trendMetric")
            }

            if entries.isEmpty {
                Text("No saved tests in the last 7 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                Chart(entries, id: \.timestamp) { entry in
                    LineMark(
                        x: .value("Time", entry.timestamp),
                        y: .value(metric.unit, metric.value(entry))
                    )
                    PointMark(
                        x: .value("Time", entry.timestamp),
                        y: .value(metric.unit, metric.value(entry))
                    )
                }
                .chartYAxisLabel(metric.unit)
                .frame(height: 120)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(accessibilityPrefix)_chart_trend")
    }
}
