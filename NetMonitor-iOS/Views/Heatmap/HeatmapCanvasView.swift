import NetMonitorCore
import SwiftUI

// MARK: - HeatmapCanvasView

/// Interactive canvas for the floor plan, heatmap overlay, measurement dots,
/// and calibration crosshairs. Supports pinch-zoom, pan, and tap-to-measure.
struct HeatmapCanvasView: View {
    @Bindable var viewModel: HeatmapSurveyViewModel

    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let imageSize = fitSize(in: geometry.size)
            let imageOrigin = CGPoint(
                x: (geometry.size.width - imageSize.width) / 2,
                y: (geometry.size.height - imageSize.height) / 2
            )

            ZStack {
                // Floor plan + overlays, transformed together
                ZStack {
                    // Floor plan image
                    if let floorImage = viewModel.floorPlanImage {
                        Image(uiImage: floorImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: imageSize.width, height: imageSize.height)
                    }

                    // Heatmap overlay
                    if let heatmapCG = viewModel.heatmapImage {
                        Image(uiImage: UIImage(cgImage: heatmapCG))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: imageSize.width, height: imageSize.height)
                            .opacity(viewModel.heatmapOpacity)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("heatmap_canvas_overlay")
                    }

                    // Measurement dots
                    ForEach(viewModel.filteredPoints) { point in
                        measurementDot(for: point, in: imageSize)
                    }

                    // Pending measurement indicator
                    if viewModel.isMeasuring, let loc = viewModel.pendingMeasurementLocation {
                        pendingIndicator(at: loc, in: imageSize)
                    }

                    // Calibration crosshairs
                    if viewModel.isCalibrating {
                        ForEach(viewModel.calibrationPoints) { point in
                            calibrationCrosshair(
                                at: CGPoint(x: point.pixelX, y: point.pixelY),
                                in: imageSize
                            )
                        }
                    }
                }
                .frame(width: imageSize.width, height: imageSize.height)
                .position(
                    x: imageOrigin.x + imageSize.width / 2 + currentOffset.width,
                    y: imageOrigin.y + imageSize.height / 2 + currentOffset.height
                )
                .scaleEffect(currentScale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(tapGesture(geometry: geometry, imageSize: imageSize, imageOrigin: imageOrigin))
            .gesture(magnificationGesture)
            .simultaneousGesture(dragGesture)
        }
        .accessibilityIdentifier("heatmap_canvas_container")
    }

    // MARK: - Measurement Dot

    private func measurementDot(for point: MeasurementPoint, in imageSize: CGSize) -> some View {
        let x = point.floorPlanX * imageSize.width
        let y = point.floorPlanY * imageSize.height
        let color = Color(uiColor: viewModel.rssiColor(point.rssi))

        return ZStack {
            // Outer glow
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 20, height: 20)
                .blur(radius: 4)

            // Inner dot
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 10, height: 10)

            // Center highlight
            Circle()
                .fill(.white.opacity(0.6))
                .frame(width: 4, height: 4)
        }
        .position(x: x, y: y)
        .accessibilityIdentifier("heatmap_dot_\(point.id.uuidString.prefix(8))")
    }

    // MARK: - Pending Indicator

    private func pendingIndicator(at location: CGPoint, in imageSize: CGSize) -> some View {
        let x = location.x * imageSize.width
        let y = location.y * imageSize.height

        return ZStack {
            Circle()
                .stroke(Theme.Colors.accent, lineWidth: 2)
                .frame(width: 24, height: 24)
                .scaleEffect(1.2)
                .opacity(0.6)

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                .scaleEffect(0.6)
        }
        .position(x: x, y: y)
        .accessibilityIdentifier("heatmap_canvas_pendingIndicator")
    }

    // MARK: - Calibration Crosshair

    private func calibrationCrosshair(at point: CGPoint, in imageSize: CGSize) -> some View {
        let x = point.x * imageSize.width
        let y = point.y * imageSize.height
        let armLength: CGFloat = 16

        return ZStack {
            // Glass background circle
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 28, height: 28)

            Circle()
                .stroke(Theme.Colors.accent, lineWidth: 2)
                .frame(width: 28, height: 28)

            // Crosshair arms
            Path { path in
                path.move(to: CGPoint(x: -armLength, y: 0))
                path.addLine(to: CGPoint(x: armLength, y: 0))
                path.move(to: CGPoint(x: 0, y: -armLength))
                path.addLine(to: CGPoint(x: 0, y: armLength))
            }
            .stroke(Theme.Colors.accent, lineWidth: 1.5)

            // Center dot
            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: 4, height: 4)
        }
        .position(x: x, y: y)
        .accessibilityIdentifier("heatmap_canvas_calibrationCrosshair")
    }

    // MARK: - Gestures

    private func tapGesture(
        geometry: GeometryProxy,
        imageSize: CGSize,
        imageOrigin: CGPoint
    ) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let tapPoint = value.location

                // Transform tap point back through scale/offset to image coordinates
                let centerX = geometry.size.width / 2
                let centerY = geometry.size.height / 2

                let transformedX = (tapPoint.x - centerX) / currentScale + centerX - currentOffset.width
                let transformedY = (tapPoint.y - centerY) / currentScale + centerY - currentOffset.height

                let relX = (transformedX - imageOrigin.x) / imageSize.width
                let relY = (transformedY - imageOrigin.y) / imageSize.height

                guard relX >= 0, relX <= 1, relY >= 0, relY <= 1 else { return }

                let normalized = CGPoint(x: relX, y: relY)

                if viewModel.isCalibrating {
                    viewModel.addCalibrationPoint(at: normalized)
                } else if viewModel.isSurveying {
                    Task<Void, Never> {
                        await viewModel.takeMeasurement(at: normalized)
                    }
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                currentScale = min(max(newScale, 0.5), 5.0)
            }
            .onEnded { _ in
                lastScale = currentScale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                currentOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = currentOffset
            }
    }

    // MARK: - Layout Helpers

    private func fitSize(in containerSize: CGSize) -> CGSize {
        guard let project = viewModel.surveyProject else {
            return CGSize(width: 300, height: 300)
        }
        let pw = CGFloat(project.floorPlan.pixelWidth)
        let ph = CGFloat(project.floorPlan.pixelHeight)
        guard pw > 0, ph > 0 else {
            return CGSize(width: 300, height: 300)
        }
        let aspectRatio = pw / ph
        let containerRatio = containerSize.width / containerSize.height
        if aspectRatio > containerRatio {
            let w = containerSize.width
            return CGSize(width: w, height: w / aspectRatio)
        } else {
            let h = containerSize.height
            return CGSize(width: h * aspectRatio, height: h)
        }
    }
}
