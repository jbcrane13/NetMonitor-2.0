import SwiftUI

// MARK: - CalibrationSheet

/// Modal sheet for two-point scale calibration of a floor plan.
/// Users drag two crosshair markers to known locations, enter the real-world
/// distance between them, and select a unit (meters/feet).
struct CalibrationSheet: View {
    @Bindable var viewModel: HeatmapSurveyViewModel
    @FocusState private var isDistanceFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            floorPlanSection
            Divider()
            controlsSection
        }
        .frame(width: 700, height: 580)
        .accessibilityIdentifier("heatmap_calibration_sheet")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Scale Calibration")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("heatmap_calibration_title")

            Text("Drag the crosshairs to two points of known distance, then enter the real-world distance between them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("heatmap_calibration_instructions")
        }
        .padding()
    }

    // MARK: - Floor Plan with Crosshairs

    private var floorPlanSection: some View {
        GeometryReader { geometry in
            ZStack {
                // Floor plan image
                if let image = viewModel.floorPlanImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .accessibilityIdentifier("heatmap_calibration_floorplan")
                }

                // First crosshair
                CrosshairMarker(color: .blue, label: "A")
                    .position(
                        x: viewModel.calibrationPoint1.x * geometry.size.width,
                        y: viewModel.calibrationPoint1.y * geometry.size.height
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                viewModel.calibrationPoint1 = normalizedPoint(
                                    value.location,
                                    in: geometry.size
                                )
                            }
                    )
                    .accessibilityIdentifier("heatmap_calibration_marker_a")

                // Second crosshair
                CrosshairMarker(color: .red, label: "B")
                    .position(
                        x: viewModel.calibrationPoint2.x * geometry.size.width,
                        y: viewModel.calibrationPoint2.y * geometry.size.height
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                viewModel.calibrationPoint2 = normalizedPoint(
                                    value.location,
                                    in: geometry.size
                                )
                            }
                    )
                    .accessibilityIdentifier("heatmap_calibration_marker_b")

                // Dashed line between markers
                Path { path in
                    path.move(to: CGPoint(
                        x: viewModel.calibrationPoint1.x * geometry.size.width,
                        y: viewModel.calibrationPoint1.y * geometry.size.height
                    ))
                    path.addLine(to: CGPoint(
                        x: viewModel.calibrationPoint2.x * geometry.size.width,
                        y: viewModel.calibrationPoint2.y * geometry.size.height
                    ))
                }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(.white.opacity(0.8))
            }
            .background(Color.black.opacity(0.05))
        }
        .frame(maxHeight: .infinity)
        .clipped()
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 16) {
            // Distance input
            HStack(spacing: 8) {
                Text("Distance:")
                    .font(.body)
                    .foregroundStyle(.primary)

                TextField("e.g. 5.0", text: $viewModel.calibrationDistance)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .focused($isDistanceFieldFocused)
                    .accessibilityIdentifier("heatmap_calibration_distance_input")
                    .onSubmit {
                        viewModel.applyCalibration()
                    }
            }

            // Unit picker
            Picker("Unit", selection: $viewModel.calibrationUnit) {
                ForEach(CalibrationUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .accessibilityIdentifier("heatmap_calibration_unit_picker")

            Spacer()

            // Action buttons
            Button("Skip") {
                viewModel.skipCalibration()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("heatmap_calibration_skip_button")

            Button("Calibrate") {
                viewModel.applyCalibration()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.calibrationDistance.isEmpty)
            .accessibilityIdentifier("heatmap_calibration_apply_button")
        }
        .padding()
    }

    // MARK: - Helpers

    /// Converts an absolute point to normalized (0-1) coordinates, clamped to bounds.
    private func normalizedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, min(1, point.x / size.width)),
            y: max(0, min(1, point.y / size.height))
        )
    }
}

// MARK: - CrosshairMarker

/// A draggable crosshair marker used for scale calibration.
struct CrosshairMarker: View {
    let color: Color
    let label: String

    var body: some View {
        ZStack {
            // Crosshair lines
            Group {
                Rectangle()
                    .frame(width: 1, height: 24)
                Rectangle()
                    .frame(width: 24, height: 1)
            }
            .foregroundStyle(color)

            // Center circle
            Circle()
                .fill(color.opacity(0.3))
                .stroke(color, lineWidth: 2)
                .frame(width: 16, height: 16)

            // Label
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(3)
                .background(color, in: RoundedRectangle(cornerRadius: 3))
                .offset(x: 14, y: -14)
        }
        .frame(width: 40, height: 40)
    }
}

#if DEBUG
#Preview("Calibration Sheet") {
    let vm = HeatmapSurveyViewModel()
    CalibrationSheet(viewModel: vm)
}
#endif
