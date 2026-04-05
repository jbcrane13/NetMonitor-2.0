import NetMonitorCore
import SwiftUI

// MARK: - HeatmapSidebarSheet

/// Bottom sheet with survey controls: mode picker, visualization picker, color scheme,
/// opacity slider, measurement list, and action buttons.
/// Phase B (#127) will implement the full interactive sidebar.
struct HeatmapSidebarSheet: View {
    let viewModel: HeatmapSurveyViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Controls row
            HStack {
                // Mode picker
                Picker("Mode", selection: Binding(
                    get: { viewModel.measurementMode },
                    set: { viewModel.measurementMode = $0 }
                )) {
                    Text("Passive").tag(HeatmapSurveyViewModel.MeasurementMode.passive)
                    Text("Active").tag(HeatmapSurveyViewModel.MeasurementMode.active)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("heatmap_picker_mode")
            }
            .padding(.horizontal)

            // Measurement count
            Text("\(viewModel.measurementPoints.count) measurements")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("heatmap_label_measurementCount")

            // Phase B (#127): visualization picker, color scheme, opacity slider,
            // measurement list, calibrate/undo/save buttons
        }
        .glassCard(cornerRadius: 20, padding: 12)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityIdentifier("heatmap_sheet_sidebar")
    }
}
