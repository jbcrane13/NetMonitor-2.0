import SwiftUI
import UniformTypeIdentifiers

// MARK: - HeatmapSurveyView

/// The main heatmap survey view for macOS.
/// Displays the floor plan with drag-and-drop support, scale bar,
/// and provides entry into the calibration workflow.
struct HeatmapSurveyView: View {
    @Bindable var viewModel: HeatmapSurveyViewModel

    var body: some View {
        Group {
            if viewModel.hasFloorPlan {
                floorPlanView
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
        .accessibilityIdentifier("heatmap_survey_view")
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

    // MARK: - Floor Plan View

    private var floorPlanView: some View {
        VStack(spacing: 0) {
            // Toolbar
            floorPlanToolbar

            Divider()

            // Floor plan canvas
            ZStack(alignment: .bottomLeading) {
                floorPlanCanvas

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
    }

    // MARK: - Floor Plan Canvas

    private var floorPlanCanvas: some View {
        GeometryReader { geometry in
            if let image = viewModel.floorPlanImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityIdentifier("heatmap_canvas_floorplan")
            }
        }
    }

    // MARK: - Toolbar

    private var floorPlanToolbar: some View {
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

            Spacer()

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
    }

    // MARK: - Scale Bar

    private var scaleBarOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Scale bar line
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

            // Scale bar label
            Text(viewModel.scaleBarLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(6)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityIdentifier("heatmap_scale_bar")
    }

    /// Computed scale bar pixel width (clamped to reasonable range).
    private var scaleBarWidth: CGFloat {
        let width = viewModel.scaleBarFraction * 500 // approximate
        return max(30, min(200, width))
    }
}

#if DEBUG
#Preview("Empty State") {
    HeatmapSurveyView(viewModel: HeatmapSurveyViewModel())
        .frame(width: 800, height: 600)
}
#endif
