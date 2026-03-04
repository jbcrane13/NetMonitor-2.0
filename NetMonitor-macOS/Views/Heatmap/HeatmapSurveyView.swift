import SwiftUI
import UniformTypeIdentifiers

// MARK: - HeatmapSurveyView

/// The main heatmap survey view for macOS.
/// Split view layout: left canvas (floor plan with measurements), right sidebar (point list + stats).
/// Toolbar provides import, calibrate, live RSSI badge, and dimension info.
struct HeatmapSurveyView: View {
    @Bindable var viewModel: HeatmapSurveyViewModel

    var body: some View {
        Group {
            if viewModel.hasFloorPlan {
                surveyContentView
            } else {
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $viewModel.isCalibrationSheetPresented) {
            CalibrationSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let msg = viewModel.errorMessage {
                Text(msg)
            }
        }
        .onAppear {
            viewModel.startLiveRSSIUpdates()
        }
        .onDisappear {
            viewModel.stopLiveRSSIUpdates()
        }
        .accessibilityIdentifier("heatmap_survey_view")
    }

    // MARK: - Split View Content

    private var surveyContentView: some View {
        VStack(spacing: 0) {
            surveyToolbar
            Divider()
            HSplitView {
                canvasSection
                    .frame(minWidth: 400)

                MeasurementSidebarView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Canvas Section (Left)

    private var canvasSection: some View {
        ZStack(alignment: .bottomLeading) {
            HeatmapCanvasView(viewModel: viewModel) { normalizedPoint in
                Task {
                    await viewModel.takeMeasurement(at: normalizedPoint)
                }
            }

            // Scale bar overlay (shown after calibration)
            if viewModel.isCalibrated {
                scaleBarOverlay
                    .padding(16)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            viewModel.handleDrop(providers: providers)
        }
    }

    // MARK: - Empty State (Import Prompt)

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("heatmap_import_icon")

            Text("Import a Floor Plan")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("heatmap_import_title")

            Text("Drag and drop an image or click Import to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("heatmap_import_subtitle")

            Text("Supported formats: PNG, JPEG, HEIC, PDF")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("heatmap_import_formats")

            Button(action: {
                viewModel.importFloorPlan()
            }) {
                Label("Import Floor Plan", systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("heatmap_import_button")
        }
        .padding(40)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            viewModel.handleDrop(providers: providers)
        }
    }

    // MARK: - Survey Toolbar

    private var surveyToolbar: some View {
        HStack(spacing: 12) {
            // Import new floor plan
            Button(action: {
                viewModel.importFloorPlan()
            }) {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("heatmap_toolbar_import")

            Divider()
                .frame(height: 20)

            // Calibration
            Button(action: {
                viewModel.startCalibration()
            }) {
                Label(
                    viewModel.isCalibrated ? "Recalibrate" : "Calibrate Scale",
                    systemImage: "ruler"
                )
            }
            .accessibilityIdentifier("heatmap_toolbar_calibrate")

            if viewModel.isCalibrated {
                Text("✓ Calibrated")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("heatmap_toolbar_calibrated_badge")
            }

            Divider()
                .frame(height: 20)

            // Live RSSI badge
            liveRSSIBadge
                .accessibilityIdentifier("heatmap_toolbar_rssi_badge")

            Spacer()

            // Measuring indicator
            if viewModel.isMeasuring {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("heatmap_toolbar_measuring_indicator")
                Text("Measuring…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Floor plan dimensions
            if let result = viewModel.importResult {
                Text("\(result.pixelWidth) × \(result.pixelHeight) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("heatmap_toolbar_dimensions")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityIdentifier("heatmap_toolbar")
    }

    // MARK: - Live RSSI Badge

    private var liveRSSIBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi")
                .font(.caption)
                .foregroundStyle(rssiColor)
            Text(viewModel.liveRSSIBadgeText)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(rssiColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private var rssiColor: Color {
        guard let rssi = viewModel.liveRSSI
        else { return .gray }
        if rssi >= -50 { return .green }
        if rssi >= -70 { return .yellow }
        return .red
    }

    // MARK: - Scale Bar

    private var scaleBarOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(.white)
                .frame(width: scaleBarWidth, height: 3)
                .overlay(
                    HStack {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 1, height: 8)
                        Spacer()
                        Rectangle()
                            .fill(.white)
                            .frame(width: 1, height: 8)
                    }
                    .frame(width: scaleBarWidth)
                )

            Text(viewModel.scaleBarLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(6)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityIdentifier("heatmap_scale_bar")
    }

    private var scaleBarWidth: CGFloat {
        let width = viewModel.scaleBarFraction * 500
        return max(30, min(200, width))
    }
}

#if DEBUG
#Preview("Empty State") {
    HeatmapSurveyView(viewModel: HeatmapSurveyViewModel())
        .frame(width: 1000, height: 700)
}
#endif
