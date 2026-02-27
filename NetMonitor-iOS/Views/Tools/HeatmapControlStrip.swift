import SwiftUI
import NetMonitorCore

// MARK: - HeatmapControlStrip

/// Compact control strip for scheme and overlay selection.
/// Adapts between horizontal (normal) and vertical (landscape full-screen sidebar).
struct HeatmapControlStrip: View {
    @Binding var colorScheme: HeatmapColorScheme
    @Binding var overlays: HeatmapDisplayOverlay
    let isSurveying: Bool
    var onStopSurvey: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            // Scheme picker
            Menu {
                ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                    Button {
                        colorScheme = scheme
                    } label: {
                        HStack {
                            Text(scheme.displayName)
                            if scheme == colorScheme { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label(colorScheme.displayName, systemImage: "thermometer.medium")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.Colors.accent.opacity(0.15))
                    .foregroundStyle(Theme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityIdentifier("heatmap_menu_scheme")

            Divider().frame(height: 20).opacity(0.3)

            // Overlay toggles
            overlayToggle("Dots", icon: "circle.fill", overlay: .dots)
            overlayToggle("Contour", icon: "waveform", overlay: .contour)
            overlayToggle("Zones", icon: "exclamationmark.triangle.fill", overlay: .deadZones)

            Spacer()

            if isSurveying {
                Button {
                    onStopSurvey?()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.Colors.error.opacity(0.15))
                        .foregroundStyle(Theme.Colors.error)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("heatmap_button_strip_stop")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func overlayToggle(_ label: String, icon: String, overlay: HeatmapDisplayOverlay) -> some View {
        let active = overlays.contains(overlay)
        return Button {
            if active { overlays.remove(overlay) } else { overlays.insert(overlay) }
        } label: {
            Label(label, systemImage: icon)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(active ? Theme.Colors.accent.opacity(0.18) : Color.white.opacity(0.06))
                .foregroundStyle(active ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .accessibilityIdentifier("heatmap_toggle_\(label.lowercased())")
    }
}
