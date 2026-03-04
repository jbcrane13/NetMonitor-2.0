import NetMonitorCore
import SwiftUI

// MARK: - VisualizationPickerSheet

/// A bottom sheet for selecting the heatmap visualization type.
/// Shows only iOS-supported types (signalStrength, downloadSpeed, latency).
struct VisualizationPickerSheet: View {
    @Binding var selected: HeatmapVisualization
    let availableTypes: [HeatmapVisualization]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Layout.itemSpacing) {
                Text("Visualization Type")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, 8)

                Text("Select which metric to display on the heatmap")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                VStack(spacing: 8) {
                    ForEach(availableTypes, id: \.self) { vizType in
                        Button {
                            selected = vizType
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: iconName(for: vizType))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(iconColor(for: vizType))
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vizType.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.Colors.textPrimary)

                                    Text(vizDescription(for: vizType))
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }

                                Spacer()

                                if selected == vizType {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selected == vizType
                                        ? Theme.Colors.accent.opacity(0.1)
                                        : Color.white.opacity(0.05))
                            )
                        }
                        .accessibilityIdentifier("heatmap_vizPicker_\(vizType.rawValue)")
                    }
                }
                .padding(.horizontal, Theme.Layout.screenPadding)

                Spacer()
            }
            .themedBackground()
        }
        .accessibilityIdentifier("heatmap_screen_vizPicker")
    }

    // MARK: - Helpers

    private func iconName(for vizType: HeatmapVisualization) -> String {
        switch vizType {
        case .signalStrength: return "wifi"
        case .signalToNoise: return "waveform.path"
        case .downloadSpeed: return "arrow.down.circle"
        case .uploadSpeed: return "arrow.up.circle"
        case .latency: return "clock"
        }
    }

    private func iconColor(for vizType: HeatmapVisualization) -> Color {
        switch vizType {
        case .signalStrength: return .cyan
        case .signalToNoise: return .purple
        case .downloadSpeed: return .green
        case .uploadSpeed: return .orange
        case .latency: return .blue
        }
    }

    private func vizDescription(for vizType: HeatmapVisualization) -> String {
        switch vizType {
        case .signalStrength: return "Wi-Fi signal strength (RSSI)"
        case .signalToNoise: return "Signal-to-noise ratio"
        case .downloadSpeed: return "Download speed (requires active scan)"
        case .uploadSpeed: return "Upload speed (requires active scan)"
        case .latency: return "Network latency (requires active scan)"
        }
    }
}

// MARK: - Preview

#Preview {
    VisualizationPickerSheet(
        selected: .constant(.signalStrength),
        availableTypes: [.signalStrength, .downloadSpeed, .latency]
    )
}
