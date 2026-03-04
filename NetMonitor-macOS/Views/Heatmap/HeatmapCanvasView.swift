import NetMonitorCore
import SwiftUI

// MARK: - HeatmapCanvasView

/// SwiftUI Canvas-based floor plan view with zoom, pan, measurement dots,
/// and coverage radius circles. Clicking the canvas triggers a measurement.
struct HeatmapCanvasView: View {
    @Bindable var viewModel: HeatmapSurveyViewModel

    /// Callback invoked when the user clicks on the canvas.
    /// Provides the normalized (0-1) coordinates of the click.
    var onCanvasClick: ((CGPoint) -> Void)?

    // MARK: - Gesture State

    /// Accumulated magnification from in-progress gesture.
    @State private var gestureZoom: CGFloat = 1.0

    /// Accumulated drag translation from in-progress gesture.
    @State private var gesturePan: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let imageSize = floorPlanAspectFitSize(in: geometry.size)
            let imageOrigin = floorPlanOrigin(imageSize: imageSize, containerSize: geometry.size)

            ZStack(alignment: .topLeading) {
                // Canvas layer: floor plan + measurement dots + coverage circles
                Canvas { context, _ in
                    drawFloorPlan(context: &context, imageSize: imageSize, imageOrigin: imageOrigin)
                    drawCoverageCircles(context: &context, imageSize: imageSize, imageOrigin: imageOrigin)
                    drawMeasurementDots(context: &context, imageSize: imageSize, imageOrigin: imageOrigin)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                // Spacing guidance text
                if viewModel.hasFloorPlan {
                    spacingGuidance
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .scaleEffect(effectiveZoom, anchor: .center)
            .offset(x: effectivePan.width, y: effectivePan.height)
            .gesture(magnifyGesture)
            .gesture(dragGesture)
            .onTapGesture { location in
                handleTap(location, containerSize: geometry.size, imageSize: imageSize, imageOrigin: imageOrigin)
            }
            .clipped()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("heatmap_canvas")
    }

    // MARK: - Spacing Guidance

    private var spacingGuidance: some View {
        Text(viewModel.spacingGuidanceText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("heatmap_spacing_guidance")
    }

    // MARK: - Gestures

    private var effectiveZoom: CGFloat {
        viewModel.zoomScale * gestureZoom
    }

    private var effectivePan: CGSize {
        CGSize(
            width: viewModel.panOffset.width + gesturePan.width,
            height: viewModel.panOffset.height + gesturePan.height
        )
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                gestureZoom = value.magnification
            }
            .onEnded { value in
                let newZoom = viewModel.zoomScale * value.magnification
                viewModel.zoomScale = max(0.25, min(10.0, newZoom))
                gestureZoom = 1.0
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                gesturePan = value.translation
            }
            .onEnded { value in
                viewModel.panOffset = CGSize(
                    width: viewModel.panOffset.width + value.translation.width,
                    height: viewModel.panOffset.height + value.translation.height
                )
                gesturePan = .zero
            }
    }

    // MARK: - Tap Handling

    private func handleTap(
        _ location: CGPoint,
        containerSize: CGSize,
        imageSize: CGSize,
        imageOrigin: CGPoint
    ) {
        // Transform screen tap location back through zoom/pan to get canvas coordinates
        let zoom = effectiveZoom
        let pan = effectivePan
        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)

        // Reverse the transforms: offset → scale → origin
        let adjustedX = (location.x - center.x - pan.width) / zoom + center.x
        let adjustedY = (location.y - center.y - pan.height) / zoom + center.y

        // Convert to normalized coordinates relative to the floor plan image
        let normalizedX = (adjustedX - imageOrigin.x) / imageSize.width
        let normalizedY = (adjustedY - imageOrigin.y) / imageSize.height

        // Only accept taps within the floor plan bounds
        guard normalizedX >= 0, normalizedX <= 1, normalizedY >= 0, normalizedY <= 1
        else { return }

        onCanvasClick?(CGPoint(x: normalizedX, y: normalizedY))
    }

    // MARK: - Drawing

    private func drawFloorPlan(
        context: inout GraphicsContext,
        imageSize: CGSize,
        imageOrigin: CGPoint
    ) {
        guard let nsImage = viewModel.floorPlanImage
        else { return }

        let rect = CGRect(origin: imageOrigin, size: imageSize)
        context.draw(Image(nsImage: nsImage), in: rect)
    }

    private func drawCoverageCircles(
        context: inout GraphicsContext,
        imageSize: CGSize,
        imageOrigin: CGPoint
    ) {
        guard let points = viewModel.project?.measurementPoints
        else { return }

        // Coverage radius: approximately 3 meters converted to image pixels,
        // then to screen points. Use a default of ~30 points if uncalibrated.
        let coverageRadiusPoints: CGFloat
        if viewModel.isCalibrated, viewModel.pixelsPerMeter > 0, let result = viewModel.importResult {
            // 3 meters * pixelsPerMeter → pixel radius → screen scale
            let pixelRadius = 3.0 * viewModel.pixelsPerMeter
            coverageRadiusPoints = CGFloat(pixelRadius) * imageSize.width / CGFloat(result.pixelWidth)
        } else {
            coverageRadiusPoints = min(imageSize.width, imageSize.height) * 0.05
        }

        for point in points {
            let screenPos = screenPosition(
                for: point,
                imageSize: imageSize,
                imageOrigin: imageOrigin
            )
            let circleRect = CGRect(
                x: screenPos.x - coverageRadiusPoints,
                y: screenPos.y - coverageRadiusPoints,
                width: coverageRadiusPoints * 2,
                height: coverageRadiusPoints * 2
            )
            context.fill(
                Circle().path(in: circleRect),
                with: .color(.blue.opacity(0.08))
            )
            context.stroke(
                Circle().path(in: circleRect),
                with: .color(.blue.opacity(0.15)),
                lineWidth: 1
            )
        }
    }

    private func drawMeasurementDots(
        context: inout GraphicsContext,
        imageSize: CGSize,
        imageOrigin: CGPoint
    ) {
        guard let points = viewModel.project?.measurementPoints
        else { return }

        for point in points {
            let isSelected = point.id == viewModel.selectedPointID
            let screenPos = screenPosition(
                for: point,
                imageSize: imageSize,
                imageOrigin: imageOrigin
            )

            // Outer glow for selected point
            if isSelected {
                let glowRect = CGRect(
                    x: screenPos.x - 14,
                    y: screenPos.y - 14,
                    width: 28,
                    height: 28
                )
                context.fill(
                    Circle().path(in: glowRect),
                    with: .color(.blue.opacity(0.3))
                )
            }

            // Measurement dot
            let dotRadius: CGFloat = isSelected ? 8 : 6
            let dotRect = CGRect(
                x: screenPos.x - dotRadius,
                y: screenPos.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(
                Circle().path(in: dotRect),
                with: .color(.blue.opacity(0.7))
            )
            context.stroke(
                Circle().path(in: dotRect),
                with: .color(.white),
                lineWidth: 1.5
            )
        }
    }

    // MARK: - Coordinate Helpers

    /// Computes the floor plan image's aspect-fit size within the container.
    private func floorPlanAspectFitSize(in containerSize: CGSize) -> CGSize {
        guard let result = viewModel.importResult
        else { return .zero }

        let imageAspect = CGFloat(result.pixelWidth) / CGFloat(result.pixelHeight)
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = containerSize.height
            return CGSize(width: height * imageAspect, height: height)
        }
    }

    /// Computes the origin to center the floor plan image within the container.
    private func floorPlanOrigin(imageSize: CGSize, containerSize: CGSize) -> CGPoint {
        CGPoint(
            x: (containerSize.width - imageSize.width) / 2,
            y: (containerSize.height - imageSize.height) / 2
        )
    }

    /// Converts a MeasurementPoint's normalized coordinates to screen position.
    private func screenPosition(
        for point: MeasurementPoint,
        imageSize: CGSize,
        imageOrigin: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: imageOrigin.x + CGFloat(point.floorPlanX) * imageSize.width,
            y: imageOrigin.y + CGFloat(point.floorPlanY) * imageSize.height
        )
    }
}

#if DEBUG
#Preview {
    HeatmapCanvasView(viewModel: HeatmapSurveyViewModel())
        .frame(width: 600, height: 400)
}
#endif
