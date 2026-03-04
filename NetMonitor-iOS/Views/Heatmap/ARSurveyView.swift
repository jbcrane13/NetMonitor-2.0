import NetMonitorCore
import SwiftUI

// MARK: - ARSurveyView

/// Survey view for Phase 2 AR-assisted surveys.
///
/// Extends the Phase 1 survey experience with AR position tracking:
/// - Blue pulsing "you are here" dot on the 2D floor plan
/// - "Measure Here" auto-places at AR position
/// - Tracking loss → manual tap fallback
/// - Floor plan editing (drag walls, delete walls, room labels)
struct ARSurveyView: View {
    @Bindable var viewModel: ARSurveyViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Canvas area
            surveyCanvas

            // Overlay content
            VStack {
                // Tracking status banner
                if let message = viewModel.trackingMessage {
                    trackingStatusBanner(message)
                        .padding(.top, 8)
                }

                Spacer()

                // Bottom controls
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
                HStack(spacing: 12) {
                    // Floor plan edit toggle
                    Button {
                        viewModel.isEditingFloorPlan.toggle()
                    } label: {
                        Image(systemName: viewModel.isEditingFloorPlan ? "pencil.circle.fill" : "pencil.circle")
                            .foregroundStyle(
                                viewModel.isEditingFloorPlan ? Theme.Colors.accent : Theme.Colors.textSecondary
                            )
                    }
                    .accessibilityIdentifier("arSurvey_button_editFloorPlan")

                    // Save button
                    Button {
                        viewModel.saveProject()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .accessibilityIdentifier("arSurvey_button_save")
                }
            }
        }
        .onAppear {
            viewModel.startHUDPolling()
            viewModel.startPositionTracking()
        }
        .onDisappear {
            viewModel.cleanup()
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
        .sheet(isPresented: $viewModel.showAddLabelSheet) {
            addLabelSheet
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
        .accessibilityIdentifier("arSurvey_screen")
    }

    // MARK: - Survey Canvas

    private var surveyCanvas: some View {
        GeometryReader { geometry in
            ARSurveyCanvasView(
                viewModel: viewModel,
                containerSize: geometry.size
            )
        }
    }

    // MARK: - Tracking Status Banner

    private func trackingStatusBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(Theme.Colors.warning)

            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(2)

            Spacer()
        }
        .padding(12)
        .background(Theme.Colors.warning.opacity(0.2))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.Layout.screenPadding)
        .accessibilityIdentifier("arSurvey_trackingBanner")
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
                .accessibilityIdentifier("arSurvey_spacingGuidance")

            HStack(spacing: 12) {
                // "Measure Here" button (auto-placement)
                if viewModel.isAutoPlacementMode {
                    Button {
                        Task {
                            await viewModel.measureAtCurrentPosition()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption.weight(.semibold))
                            Text("Measure Here")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                                .fill(Theme.Colors.accent)
                        )
                    }
                    .disabled(viewModel.isMeasuring)
                    .accessibilityIdentifier("arSurvey_button_measureHere")
                }

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
                .accessibilityIdentifier("arSurvey_vizPicker")

                if viewModel.isMeasuring {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                            .scaleEffect(0.7)
                        Text("Measuring…")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .accessibilityIdentifier("arSurvey_measuringIndicator")
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)

            // Floor plan editing controls
            if viewModel.isEditingFloorPlan {
                floorPlanEditControls
            }
        }
    }

    // MARK: - Floor Plan Edit Controls

    private var floorPlanEditControls: some View {
        HStack(spacing: 12) {
            Button {
                // Add label at center of view
                viewModel.pendingLabelPosition = (x: 0.5, y: 0.5)
                viewModel.showAddLabelSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.caption.weight(.semibold))
                    Text("Add Label")
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
            }
            .accessibilityIdentifier("arSurvey_button_addLabel")

            Text("Tap walls to select • Drag endpoints to adjust")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .accessibilityIdentifier("arSurvey_editControls")
    }

    // MARK: - Add Label Sheet

    private var addLabelSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                Text("Add Room Label")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                TextField("Room name (e.g., Living Room)", text: $viewModel.pendingLabelText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .accessibilityIdentifier("arSurvey_textField_labelName")

                HStack(spacing: 16) {
                    Button("Cancel") {
                        viewModel.showAddLabelSheet = false
                        viewModel.pendingLabelText = ""
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)

                    Button("Add") {
                        if let pos = viewModel.pendingLabelPosition,
                           !viewModel.pendingLabelText.isEmpty {
                            viewModel.addRoomLabel(
                                text: viewModel.pendingLabelText,
                                atNormalizedX: pos.x,
                                y: pos.y
                            )
                        }
                        viewModel.showAddLabelSheet = false
                        viewModel.pendingLabelText = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.pendingLabelText.isEmpty)
                    .accessibilityIdentifier("arSurvey_button_confirmLabel")
                }
            }
            .padding()
            .presentationDetents([.height(200)])
        }
    }
}

// MARK: - ARSurveyCanvasView

/// The interactive floor plan canvas with AR position tracking,
/// measurement markers, heatmap overlay, and floor plan editing.
private struct ARSurveyCanvasView: View {
    @Bindable var viewModel: ARSurveyViewModel
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

                    // Heatmap overlay
                    if let overlay = viewModel.heatmapOverlay {
                        Image(decorative: overlay, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: imageSize.width, height: imageSize.height)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("arSurvey_heatmapOverlay")
                    }

                    // Room labels
                    ForEach(viewModel.roomLabels) { label in
                        RoomLabelView(
                            label: label,
                            imageSize: imageSize,
                            isEditing: viewModel.isEditingFloorPlan,
                            onDelete: {
                                viewModel.deleteRoomLabel(label)
                            }
                        )
                    }

                    // Measurement markers
                    ForEach(viewModel.project.measurementPoints) { point in
                        MeasurementMarkerView(
                            point: point,
                            imageSize: imageSize,
                            containerSize: containerSize,
                            isInspected: viewModel.inspectedPoint?.id == point.id
                        )
                        .onTapGesture {
                            viewModel.inspectPoint(point)
                        }
                        .onLongPressGesture {
                            viewModel.deletePoint(point)
                        }
                    }

                    // Blue pulsing "you are here" dot
                    if viewModel.showPositionDot, let position = viewModel.currentPositionOnPlan {
                        YouAreHereDot(
                            normalizedX: position.x,
                            normalizedY: position.y,
                            imageSize: imageSize,
                            containerSize: containerSize
                        )
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
                    // Manual tap fallback when tracking is lost
                    if !viewModel.isAutoPlacementMode {
                        handleTap(at: location, imageSize: imageSize)
                    }
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
        .accessibilityIdentifier("arSurvey_canvas")
    }

    // MARK: - Tap Handling (Manual Fallback)

    private func handleTap(at location: CGPoint, imageSize: CGSize) {
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2

        let adjustedX = (location.x - centerX - currentOffset.width) / currentScale + centerX
        let adjustedY = (location.y - centerY - currentOffset.height) / currentScale + centerY

        let imageOriginX = (containerSize.width - imageSize.width) / 2
        let imageOriginY = (containerSize.height - imageSize.height) / 2

        let imageX = adjustedX - imageOriginX
        let imageY = adjustedY - imageOriginY

        let normalizedX = imageX / imageSize.width
        let normalizedY = imageY / imageSize.height

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

// MARK: - YouAreHereDot

/// Blue pulsing "you are here" dot showing the user's AR-tracked position.
private struct YouAreHereDot: View {
    let normalizedX: Double
    let normalizedY: Double
    let imageSize: CGSize
    let containerSize: CGSize

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .stroke(Color.blue.opacity(isPulsing ? 0 : 0.6), lineWidth: 2)
                .frame(width: 24, height: 24)
                .scaleEffect(isPulsing ? 2.0 : 1.0)

            // Glow ring
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 20, height: 20)

            // Center dot
            Circle()
                .fill(Color.blue)
                .frame(width: 12, height: 12)
                .shadow(color: .blue.opacity(0.6), radius: 6)

            // Inner white dot
            Circle()
                .fill(.white)
                .frame(width: 4, height: 4)
        }
        .position(
            x: normalizedX * imageSize.width,
            y: normalizedY * imageSize.height
        )
        .offset(
            x: (containerSize.width - imageSize.width) / 2,
            y: (containerSize.height - imageSize.height) / 2
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("arSurvey_youAreHereDot")
    }
}

// MARK: - MeasurementMarkerView

/// A blue marker for a measurement point on the AR survey canvas.
private struct MeasurementMarkerView: View {
    let point: MeasurementPoint
    let imageSize: CGSize
    let containerSize: CGSize
    let isInspected: Bool

    @State private var isPulsing = false

    private let markerRadius: CGFloat = 8
    private let coverageRadius: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.1))
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                .frame(width: coverageRadius * 2, height: coverageRadius * 2)

            Circle()
                .fill(Color.blue.opacity(0.8))
                .frame(width: markerRadius * 2, height: markerRadius * 2)
                .shadow(color: .blue.opacity(0.5), radius: 4)

            Circle()
                .stroke(Color.blue.opacity(isPulsing ? 0 : 0.6), lineWidth: 2)
                .frame(width: markerRadius * 2, height: markerRadius * 2)
                .scaleEffect(isPulsing ? 2.5 : 1.0)
                .animation(.easeOut(duration: 1.0), value: isPulsing)

            if isInspected {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: markerRadius * 2 + 6, height: markerRadius * 2 + 6)
            }
        }
        .position(
            x: point.floorPlanX * imageSize.width,
            y: point.floorPlanY * imageSize.height
        )
        .offset(
            x: (containerSize.width - imageSize.width) / 2,
            y: (containerSize.height - imageSize.height) / 2
        )
        .onAppear {
            isPulsing = true
        }
        .accessibilityIdentifier("arSurvey_marker_\(point.id.uuidString)")
    }
}

// MARK: - RoomLabelView

/// Renders a room label on the floor plan canvas.
private struct RoomLabelView: View {
    let label: RoomLabel
    let imageSize: CGSize
    let isEditing: Bool
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Text(label.text)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isEditing ? Theme.Colors.accent : Theme.Colors.glassBorder,
                            lineWidth: isEditing ? 1.5 : 0.5
                        )
                )
                .contextMenu {
                    if isEditing {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete Label", systemImage: "trash")
                        }
                    }
                }
        }
        .position(
            x: label.floorPlanX * imageSize.width,
            y: label.floorPlanY * imageSize.height
        )
        .accessibilityIdentifier("arSurvey_label_\(label.id.uuidString)")
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
        origin: .arGenerated
    )
    let project = SurveyProject(name: "AR Survey", floorPlan: floorPlan, surveyMode: .arAssisted)

    NavigationStack {
        Text("Preview placeholder")
    }
}
