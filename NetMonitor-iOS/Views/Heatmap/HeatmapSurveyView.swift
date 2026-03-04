import NetMonitorCore
import SwiftUI

// MARK: - HeatmapSurveyView

/// Main survey view for the iOS Wi-Fi heatmap walk survey.
/// Displays the floor plan canvas with measurement markers, heatmap overlay,
/// floating RSSI HUD, spacing guidance, and visualization picker.
struct HeatmapSurveyView: View {
    @Bindable var viewModel: HeatmapSurveyViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Canvas area (full screen behind nav bar)
            surveyCanvas

            // Floating HUD overlay
            VStack {
                Spacer()

                // Bottom controls: spacing guidance + viz picker + save
                bottomControls

                // Floating RSSI HUD
                FloatingRSSIHUD(
                    rssi: viewModel.liveRSSI,
                    ssid: viewModel.liveSSID,
                    pointCount: viewModel.pointCount
                )
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.bottom, 8)
            }
        }
        .themedBackground()
        .navigationTitle(viewModel.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.saveProject()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityIdentifier("heatmap_survey_save")
            }
        }
        .onAppear {
            viewModel.startHUDPolling()
        }
        .onDisappear {
            viewModel.stopHUDPolling()
        }
        .sheet(item: $viewModel.inspectedPoint) { point in
            MeasurementDetailSheet(
                point: point,
                onDelete: {
                    viewModel.deletePoint(point)
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $viewModel.showVisualizationPicker) {
            VisualizationPickerSheet(
                selected: $viewModel.selectedVisualization,
                availableTypes: viewModel.availableVisualizations
            )
            .presentationDetents([.height(280)])
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .accessibilityIdentifier("heatmap_screen_survey")
    }

    // MARK: - Survey Canvas

    private var surveyCanvas: some View {
        GeometryReader { geometry in
            SurveyCanvasView(
                viewModel: viewModel,
                containerSize: geometry.size
            )
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 8) {
            // Spacing guidance
            Text(viewModel.spacingGuidance)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Layout.screenPadding)
                .accessibilityIdentifier("heatmap_survey_spacingGuidance")

            // Visualization picker button + measuring indicator
            HStack(spacing: 12) {
                // Viz picker
                Button {
                    viewModel.showVisualizationPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paintpalette.fill")
                            .font(.caption.weight(.semibold))
                        Text(viewModel.selectedVisualization.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.Colors.glassBorder, lineWidth: 0.5)
                    )
                }
                .accessibilityIdentifier("heatmap_survey_vizPicker")

                if viewModel.isMeasuring {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                            .scaleEffect(0.7)
                        Text("Measuring…")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .accessibilityIdentifier("heatmap_survey_measuringIndicator")
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
        }
    }
}

// MARK: - SurveyCanvasView

/// The interactive floor plan canvas with measurement markers and heatmap overlay.
private struct SurveyCanvasView: View {
    @Bindable var viewModel: HeatmapSurveyViewModel
    let containerSize: CGSize

    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    var body: some View {
        ZStack {
            if let image = viewModel.floorPlanImage {
                let imageSize = aspectFitSize(
                    for: image.size,
                    in: containerSize
                )

                ZStack {
                    // Floor plan base layer
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageSize.width, height: imageSize.height)

                    // Heatmap overlay (70% opacity, rendered by HeatmapRenderer)
                    if let overlay = viewModel.heatmapOverlay {
                        Image(decorative: overlay, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: imageSize.width, height: imageSize.height)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("heatmap_survey_overlay")
                    }

                    // Measurement markers
                    ForEach(viewModel.project.measurementPoints) { point in
                        MeasurementMarker(
                            point: point,
                            imageSize: imageSize,
                            isInspected: viewModel.inspectedPoint?.id == point.id
                        )
                        .onTapGesture {
                            viewModel.inspectPoint(point)
                        }
                        .onLongPressGesture {
                            viewModel.deletePoint(point)
                        }
                    }
                }
                .scaleEffect(currentScale)
                .offset(currentOffset)
                .gesture(magnifyGesture)
                .gesture(dragGesture)
                .frame(width: containerSize.width, height: containerSize.height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { location in
                    handleTap(at: location, imageSize: imageSize)
                }
            } else {
                // No floor plan loaded
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("No floor plan loaded")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .accessibilityIdentifier("heatmap_survey_canvas")
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint, imageSize: CGSize) {
        // Convert screen location to normalized floor plan coordinates (0-1)
        // Account for current zoom and offset
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2

        // Reverse the offset and scale transformations
        let adjustedX = (location.x - centerX - currentOffset.width) / currentScale + centerX
        let adjustedY = (location.y - centerY - currentOffset.height) / currentScale + centerY

        // Convert to image-relative coordinates
        let imageOriginX = (containerSize.width - imageSize.width) / 2
        let imageOriginY = (containerSize.height - imageSize.height) / 2

        let imageX = adjustedX - imageOriginX
        let imageY = adjustedY - imageOriginY

        // Normalize to 0-1
        let normalizedX = imageX / imageSize.width
        let normalizedY = imageY / imageSize.height

        // Validate bounds
        guard normalizedX >= 0, normalizedX <= 1, normalizedY >= 0, normalizedY <= 1 else {
            return
        }

        Task {
            await viewModel.takeMeasurement(atNormalizedX: normalizedX, y: normalizedY)
        }
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                currentScale = min(maxScale, max(minScale, newScale))
            }
            .onEnded { _ in
                lastScale = currentScale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
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

    // MARK: - Helpers

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

// MARK: - MeasurementMarker

/// A blue marker for a measurement point on the canvas.
private struct MeasurementMarker: View {
    let point: MeasurementPoint
    let imageSize: CGSize
    let isInspected: Bool

    @State private var isPulsing = false

    private let markerRadius: CGFloat = 8
    private let coverageRadius: CGFloat = 24

    var body: some View {
        ZStack {
            // Coverage radius circle
            Circle()
                .fill(Color.blue.opacity(0.1))
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                .frame(width: coverageRadius * 2, height: coverageRadius * 2)

            // Center dot
            Circle()
                .fill(Color.blue.opacity(0.8))
                .frame(width: markerRadius * 2, height: markerRadius * 2)
                .shadow(color: .blue.opacity(0.5), radius: 4)

            // Pulse animation for new point
            Circle()
                .stroke(Color.blue.opacity(isPulsing ? 0 : 0.6), lineWidth: 2)
                .frame(width: markerRadius * 2, height: markerRadius * 2)
                .scaleEffect(isPulsing ? 2.5 : 1.0)
                .animation(.easeOut(duration: 1.0), value: isPulsing)

            // Inspection highlight
            if isInspected {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: markerRadius * 2 + 6, height: markerRadius * 2 + 6)
            }
        }
        .position(
            x: point.floorPlanX * imageSize.width + (imageSize.width > 0 ? 0 : 0),
            y: point.floorPlanY * imageSize.height
        )
        .offset(
            x: (UIScreen.main.bounds.width - imageSize.width) / 2,
            y: (UIScreen.main.bounds.height - imageSize.height) / 2
        )
        .onAppear {
            isPulsing = true
        }
        .accessibilityIdentifier("heatmap_marker_\(point.id.uuidString)")
    }
}

// MARK: - Preview

#Preview {
    let floorPlan = FloorPlan(
        imageData: Data(),
        widthMeters: 10,
        heightMeters: 8,
        pixelWidth: 800,
        pixelHeight: 600,
        origin: .drawn
    )
    let project = SurveyProject(name: "Test", floorPlan: floorPlan)

    NavigationStack {
        Text("Preview placeholder")
    }
}
