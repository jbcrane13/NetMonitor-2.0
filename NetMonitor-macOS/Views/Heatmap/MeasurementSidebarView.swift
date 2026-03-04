import NetMonitorCore
import SwiftUI

// MARK: - MeasurementSidebarView

/// Right sidebar for the heatmap survey view.
/// Shows summary statistics at the top and a scrollable list of measurement points.
/// Clicking a point highlights it on the canvas.
struct MeasurementSidebarView: View {
    @Bindable var viewModel: HeatmapSurveyViewModel

    var body: some View {
        VStack(spacing: 0) {
            summaryStatsSection
            Divider()
            measurementListSection
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
        .accessibilityIdentifier("heatmap_measurement_sidebar")
    }

    // MARK: - Summary Statistics

    private var summaryStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Survey Summary")
                .font(.headline)
                .accessibilityIdentifier("heatmap_sidebar_summary_title")

            let stats = viewModel.summaryStats
            if viewModel.project?.measurementPoints.isEmpty == false {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    StatCell(
                        label: "Points",
                        value: "\(stats.count)",
                        identifier: "heatmap_sidebar_stat_count"
                    )
                    StatCell(
                        label: "Avg RSSI",
                        value: String(format: "%.0f dBm", stats.avgRSSI),
                        identifier: "heatmap_sidebar_stat_avg"
                    )
                    StatCell(
                        label: "Min RSSI",
                        value: "\(stats.minRSSI) dBm",
                        identifier: "heatmap_sidebar_stat_min"
                    )
                    StatCell(
                        label: "Max RSSI",
                        value: "\(stats.maxRSSI) dBm",
                        identifier: "heatmap_sidebar_stat_max"
                    )
                    StatCell(
                        label: "Coverage",
                        value: String(format: "%.0f m²", stats.coverageAreaSqM),
                        identifier: "heatmap_sidebar_stat_coverage"
                    )
                }
            } else {
                Text("No measurements yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("heatmap_sidebar_empty")
            }
        }
        .padding(12)
        .accessibilityIdentifier("heatmap_sidebar_stats")
    }

    // MARK: - Measurement List

    private var measurementListSection: some View {
        Group {
            if let points = viewModel.project?.measurementPoints, !points.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(points) { point in
                            MeasurementRowView(
                                point: point,
                                isSelected: point.id == viewModel.selectedPointID
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if viewModel.selectedPointID == point.id {
                                    viewModel.selectedPointID = nil
                                } else {
                                    viewModel.selectedPointID = point.id
                                }
                            }
                            .accessibilityIdentifier("heatmap_sidebar_point_\(point.id.uuidString.prefix(8))")
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                VStack {
                    Spacer()
                    Text("Click on the floor plan to add measurements")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            }
        }
        .accessibilityIdentifier("heatmap_sidebar_point_list")
    }
}

// MARK: - StatCell

/// A small cell showing a label and value pair.
private struct StatCell: View {
    let label: String
    let value: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - MeasurementRowView

/// A single row in the measurement point list.
private struct MeasurementRowView: View {
    let point: MeasurementPoint
    let isSelected: Bool

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .medium
        return fmt
    }()

    var body: some View {
        HStack(spacing: 8) {
            // RSSI indicator circle
            Circle()
                .fill(rssiColor)
                .frame(width: 10, height: 10)

            // Point info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(point.rssi) dBm")
                        .font(.callout)
                        .fontWeight(.medium)
                    if let ssid = point.ssid {
                        Text("· \(ssid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(Self.timeFormatter.string(from: point.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Channel/band badge
            if let channel = point.channel {
                Text("Ch \(channel)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private var rssiColor: Color {
        let rssi = point.rssi
        if rssi >= -50 {
            return .green
        } else if rssi >= -70 {
            return .yellow
        } else {
            return .red
        }
    }
}

#if DEBUG
#Preview {
    MeasurementSidebarView(viewModel: HeatmapSurveyViewModel())
        .frame(width: 300, height: 500)
}
#endif
