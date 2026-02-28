import SwiftUI
import NetMonitorCore

// MARK: - HeatmapResultView

/// Read-only viewer for a completed and saved WiFi heatmap survey.
struct HeatmapResultView: View {
    let survey: HeatmapSurvey
    @Bindable var viewModel: WiFiHeatmapSurveyViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showingFullScreen = false
    @State private var localPoints: [HeatmapDataPoint] = []

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                summaryCard
                canvasSection
                HeatmapControlStrip(
                    colorScheme: $viewModel.colorScheme,
                    overlays: $viewModel.displayOverlays,
                    isSurveying: false,
                    onStopSurvey: {}
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
                MeasurementsPanel(
                    points: survey.dataPoints,
                    isSurveying: false,
                    calibration: survey.calibration,
                    preferredUnit: $viewModel.preferredUnit
                )
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle(survey.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.Colors.error)
                }
                .accessibilityIdentifier("heatmap_result_button_delete")
            }
        }
        .confirmationDialog("Delete this survey?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Survey", role: .destructive) {
                viewModel.deleteSurvey(survey)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            HeatmapFullScreenView(
                points: $localPoints,
                floorplanImage: nil,
                colorScheme: $viewModel.colorScheme,
                overlays: $viewModel.displayOverlays,
                calibration: survey.calibration,
                isSurveying: false,
                onTap: nil,
                onStopSurvey: nil,
                onDismiss: { showingFullScreen = false }
            )
        }
        .onAppear { localPoints = survey.dataPoints }
        .accessibilityIdentifier("screen_heatmapResult")
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(survey.mode.displayName, systemImage: survey.mode.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.Colors.accent.opacity(0.12))
                        .clipShape(Capsule())

                    Spacer()

                    if survey.calibration != nil {
                        Label("Calibrated", systemImage: "ruler")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }

                HStack(spacing: 24) {
                    statItem(value: "\(survey.dataPoints.count)", label: "Measurements")

                    if let avg = survey.averageSignal {
                        statItem(value: "\(avg)", label: "Avg dBm")
                        if let level = survey.signalLevel {
                            statItem(value: level.label, label: "Signal")
                        }
                    }
                }

                Text(survey.createdAt.formatted(date: .long, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .accessibilityIdentifier("heatmap_result_summary_card")
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Canvas

    private var canvasSection: some View {
        ZStack {
            HeatmapCanvasView(
                points: survey.dataPoints,
                floorplanImage: nil,
                colorScheme: viewModel.colorScheme,
                overlays: viewModel.displayOverlays,
                calibration: survey.calibration,
                isSurveying: false,
                onTap: nil
            )
            .frame(height: 300)

            Button {
                showingFullScreen = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(10)
            .accessibilityIdentifier("heatmap_result_button_fullscreen")
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
