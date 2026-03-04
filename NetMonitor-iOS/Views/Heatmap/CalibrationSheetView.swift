import SwiftUI

// MARK: - CalibrationSheetView

/// Touch-optimized calibration sheet for iOS.
/// Users drag two crosshair markers to known locations, enter the real-world
/// distance between them, and select a unit (meters/feet).
struct CalibrationSheetView: View {
    @Bindable var viewModel: FloorPlanImportViewModel
    @FocusState private var isDistanceFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Instructions
            instructionsSection

            // Floor plan with crosshairs
            floorPlanSection

            Divider()
                .background(Theme.Colors.glassBorder)

            // Controls
            controlsSection
        }
        .themedBackground()
        .navigationTitle("Scale Calibration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") {
                    viewModel.skipCalibration()
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("heatmap_calibration_skip")
            }
        }
        .accessibilityIdentifier("heatmap_screen_calibration")
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(spacing: 4) {
            Text("Drag the markers to two points of known distance, then enter the real-world distance between them.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.vertical, 8)
        }
        .accessibilityIdentifier("heatmap_calibration_instructions")
    }

    // MARK: - Floor Plan with Crosshairs

    private var floorPlanSection: some View {
        GeometryReader { geometry in
            ZStack {
                // Floor plan image
                if let image = viewModel.floorPlanImage {
                    let imageSize = aspectFitSize(for: image.size, in: geometry.size)
                    let imageOrigin = CGPoint(
                        x: (geometry.size.width - imageSize.width) / 2,
                        y: (geometry.size.height - imageSize.height) / 2
                    )

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .accessibilityIdentifier("heatmap_calibration_floorplan")

                    // Dashed line between markers
                    Path { path in
                        path.move(to: markerPosition(
                            viewModel.calibrationPoint1,
                            imageOrigin: imageOrigin,
                            imageSize: imageSize
                        ))
                        path.addLine(to: markerPosition(
                            viewModel.calibrationPoint2,
                            imageOrigin: imageOrigin,
                            imageSize: imageSize
                        ))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(.white.opacity(0.8))

                    // First crosshair marker — touch-optimized
                    TouchCrosshairMarker(color: .blue, label: "A")
                        .position(markerPosition(
                            viewModel.calibrationPoint1,
                            imageOrigin: imageOrigin,
                            imageSize: imageSize
                        ))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    viewModel.calibrationPoint1 = normalizedPoint(
                                        value.location,
                                        imageOrigin: imageOrigin,
                                        imageSize: imageSize
                                    )
                                }
                        )
                        .accessibilityIdentifier("heatmap_calibration_marker_a")

                    // Second crosshair marker — touch-optimized
                    TouchCrosshairMarker(color: .red, label: "B")
                        .position(markerPosition(
                            viewModel.calibrationPoint2,
                            imageOrigin: imageOrigin,
                            imageSize: imageSize
                        ))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    viewModel.calibrationPoint2 = normalizedPoint(
                                        value.location,
                                        imageOrigin: imageOrigin,
                                        imageSize: imageSize
                                    )
                                }
                        )
                        .accessibilityIdentifier("heatmap_calibration_marker_b")
                }
            }
            .background(Color.black.opacity(0.3))
        }
        .frame(maxHeight: .infinity)
        .clipped()
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            // Distance input row
            HStack(spacing: Theme.Layout.itemSpacing) {
                Text("Distance:")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                TextField("e.g. 5.0", text: $viewModel.calibrationDistance)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Layout.smallCornerRadius)
                            .fill(Color.white.opacity(0.08))
                    )
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 100)
                    .focused($isDistanceFieldFocused)
                    .accessibilityIdentifier("heatmap_calibration_distance_input")
            }

            // Unit picker
            Picker("Unit", selection: $viewModel.calibrationUnit) {
                ForEach(CalibrationUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("heatmap_calibration_unit_picker")

            // Apply button
            Button {
                viewModel.applyCalibration()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                    Text("Apply Calibration")
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                        .fill(Theme.Colors.accent)
                )
            }
            .disabled(viewModel.calibrationDistance.isEmpty)
            .opacity(viewModel.calibrationDistance.isEmpty ? 0.5 : 1.0)
            .accessibilityIdentifier("heatmap_calibration_apply")
        }
        .padding(Theme.Layout.screenPadding)
    }

    // MARK: - Coordinate Helpers

    /// Converts a normalized (0-1) point to absolute position within the image area.
    private func markerPosition(
        _ normalized: CGPoint,
        imageOrigin: CGPoint,
        imageSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: imageOrigin.x + normalized.x * imageSize.width,
            y: imageOrigin.y + normalized.y * imageSize.height
        )
    }

    /// Converts an absolute drag position to a normalized (0-1) point within the image area.
    private func normalizedPoint(
        _ point: CGPoint,
        imageOrigin: CGPoint,
        imageSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: max(0, min(1, (point.x - imageOrigin.x) / imageSize.width)),
            y: max(0, min(1, (point.y - imageOrigin.y) / imageSize.height))
        )
    }

    /// Computes the aspect-fit size for an image within a container.
    private func aspectFitSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }
}

// MARK: - TouchCrosshairMarker

/// A touch-optimized crosshair marker for iOS calibration.
/// Larger hit area than macOS version for better touch targeting.
struct TouchCrosshairMarker: View {
    let color: Color
    let label: String

    var body: some View {
        ZStack {
            // Large invisible hit area for touch targeting
            Circle()
                .fill(Color.clear)
                .frame(width: 56, height: 56)

            // Crosshair lines
            Group {
                Rectangle()
                    .frame(width: 1.5, height: 30)
                Rectangle()
                    .frame(width: 30, height: 1.5)
            }
            .foregroundStyle(color)

            // Center circle with outer ring
            Circle()
                .fill(color.opacity(0.3))
                .stroke(color, lineWidth: 2.5)
                .frame(width: 20, height: 20)

            // Label badge
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(color, in: RoundedRectangle(cornerRadius: 4))
                .offset(x: 18, y: -18)
        }
        .frame(width: 56, height: 56)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CalibrationSheetView(viewModel: FloorPlanImportViewModel())
    }
}
