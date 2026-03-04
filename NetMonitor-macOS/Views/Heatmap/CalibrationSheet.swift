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
            let imageDisplaySize = imageDisplaySize(in: geometry.size)
            let origin = FloorPlanLayoutHelper.imageOrigin(
                imageDisplaySize: imageDisplaySize,
                containerSize: geometry.size
            )

            ZStack {
                // Floor plan image
                if let image = viewModel.floorPlanImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .accessibilityIdentifier("heatmap_calibration_floorplan")
                }

                // First crosshair — positioned relative to actual image display rect
                CrosshairMarker(color: .blue, label: "A")
                    .position(
                        FloorPlanLayoutHelper.absolutePosition(
                            from: viewModel.calibrationPoint1,
                            imageOrigin: origin,
                            imageDisplaySize: imageDisplaySize
                        )
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                viewModel.calibrationPoint1 = FloorPlanLayoutHelper.normalizedPosition(
                                    from: value.location,
                                    imageOrigin: origin,
                                    imageDisplaySize: imageDisplaySize
                                )
                            }
                    )
                    .accessibilityIdentifier("heatmap_calibration_marker_a")

                // Second crosshair — positioned relative to actual image display rect
                CrosshairMarker(color: .red, label: "B")
                    .position(
                        FloorPlanLayoutHelper.absolutePosition(
                            from: viewModel.calibrationPoint2,
                            imageOrigin: origin,
                            imageDisplaySize: imageDisplaySize
                        )
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                viewModel.calibrationPoint2 = FloorPlanLayoutHelper.normalizedPosition(
                                    from: value.location,
                                    imageOrigin: origin,
                                    imageDisplaySize: imageDisplaySize
                                )
                            }
                    )
                    .accessibilityIdentifier("heatmap_calibration_marker_b")

                // Dashed line between markers
                Path { path in
                    let point1Pos = FloorPlanLayoutHelper.absolutePosition(
                        from: viewModel.calibrationPoint1,
                        imageOrigin: origin,
                        imageDisplaySize: imageDisplaySize
                    )
                    let point2Pos = FloorPlanLayoutHelper.absolutePosition(
                        from: viewModel.calibrationPoint2,
                        imageOrigin: origin,
                        imageDisplaySize: imageDisplaySize
                    )
                    path.move(to: point1Pos)
                    path.addLine(to: point2Pos)
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

    /// Computes the aspect-fit display size for the floor plan image within the container.
    private func imageDisplaySize(in containerSize: CGSize) -> CGSize {
        guard let result = viewModel.importResult
        else { return containerSize }

        return FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: result.pixelWidth,
            imagePixelHeight: result.pixelHeight,
            containerSize: containerSize
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
