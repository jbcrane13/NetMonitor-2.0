import SwiftUI
import NetMonitorCore

// MARK: - WiFiHeatmapSurveyView

/// Full-screen active WiFi mapping canvas.
/// Auto-starts the survey on appear and saves on dismiss.
struct WiFiHeatmapSurveyView: View {
    @Bindable var viewModel: WiFiHeatmapSurveyViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var recordingPulse = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-screen canvas — fills space between nav bar and tab bar
            HeatmapCanvasView(
                points: viewModel.dataPoints,
                floorplanImage: viewModel.floorplanImageData.flatMap(UIImage.init),
                colorScheme: viewModel.colorScheme,
                overlays: viewModel.displayOverlays,
                calibration: viewModel.calibration,
                isSurveying: viewModel.isSurveying,
                onTap: { loc, size in viewModel.recordDataPoint(at: loc, in: size) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Drop-point hint when no measurements yet
            if viewModel.dataPoints.isEmpty {
                Text("Tap to drop survey points")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Bottom stats HUD
            bottomHUD
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.bottom, Theme.Layout.itemSpacing)
        }
        .themedBackground()
        .navigationTitle("Active Mapping")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.stopSurvey()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .accessibilityIdentifier("heatmap_survey_button_close")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Circle()
                    .fill(Theme.Colors.error)
                    .frame(width: 10, height: 10)
                    .opacity(recordingPulse ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                               value: recordingPulse)
            }
        }
        .onAppear {
            if !viewModel.isSurveying { viewModel.startSurvey() }
            recordingPulse = true
        }
        .onDisappear {
            viewModel.stopSurvey()
        }
        .accessibilityIdentifier("screen_activeMappingSurvey")
    }

    // MARK: - Bottom HUD

    private var bottomHUD: some View {
        HStack(spacing: 0) {
            statCell(
                value: viewModel.isSurveying ? viewModel.signalText : "--",
                label: "SIGNAL",
                valueColor: viewModel.signalColor
            )
            hudDivider
            statCell(
                value: "\(viewModel.dataPoints.count)",
                label: "NODES",
                valueColor: Theme.Colors.textPrimary
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var hudDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 44)
    }

    private func statCell(value: String, label: String, valueColor: Color) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(1.5)
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(value == "--" ? Theme.Colors.textTertiary : valueColor)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack { WiFiHeatmapSurveyView(viewModel: WiFiHeatmapSurveyViewModel()) }
}
