import SwiftUI
import NetMonitorCore

// MARK: - MeasurementsPanel

/// Shows live stats during survey and full stats after completion.
struct MeasurementsPanel: View {
    let points: [HeatmapDataPoint]
    let isSurveying: Bool
    let calibration: CalibrationScale?
    @Binding var preferredUnit: DistanceUnit

    private var stats: HeatmapRenderer.SurveyStats {
        HeatmapRenderer.computeStats(points: points, calibration: calibration, unit: preferredUnit)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack {
                    Text(isSurveying ? "Live Stats" : "Measurements")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if calibration != nil {
                        Picker("", selection: $preferredUnit) {
                            ForEach(DistanceUnit.allCases, id: \.self) { u in
                                Text(u.displayName).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                        .accessibilityIdentifier("measurements_picker_unit")
                    }
                }

                if points.isEmpty {
                    Text("Tap the canvas to record signal at each location")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        statCell(value: "\(stats.count)", label: "Points")
                        statCell(value: stats.averageDBm.map { "\($0) dBm" } ?? "--",
                                 label: "Average", color: colorFor(stats.averageDBm))
                        statCell(value: stats.strongestDBm.map { "\($0) dBm" } ?? "--",
                                 label: "Strongest", color: successColor)
                        statCell(value: stats.weakestDBm.map { "\($0) dBm" } ?? "--",
                                 label: "Weakest", color: errorColor)
                        statCell(value: stats.strongCoveragePercent.map { "\($0)%" } ?? "--",
                                 label: "Strong coverage")
                        if calibration == nil {
                            statCell(value: "—", label: "Calibrate for scale", color: Theme.Colors.textTertiary)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("heatmap_section_measurements")
    }

    private func statCell(value: String, label: String, color: Color = Theme.Colors.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func colorFor(_ rssi: Int?) -> Color {
        guard let r = rssi else { return Theme.Colors.textPrimary }
        switch SignalLevel.from(rssi: r) {
        case .strong: return successColor
        case .fair:   return warningColor
        case .weak:   return errorColor
        }
    }

    // Use Theme.Colors.success/warning/error — confirmed present in Theme.swift
    private var successColor: Color { Theme.Colors.success }
    private var warningColor: Color { Theme.Colors.warning }
    private var errorColor: Color   { Theme.Colors.error }
}
