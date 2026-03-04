import NetMonitorCore
import SwiftUI

// MARK: - PostScanReviewView

/// Full-screen post-scan review for Phase 3 continuous scan results.
///
/// Features:
/// - Full-screen map with heatmap overlay (zoom + pan)
/// - Visualization picker (signal strength, download speed, latency)
/// - AP roaming overlay toggle (P1)
/// - Walking path toggle (P1)
/// - Coverage completeness indicator (P1)
/// - Share/export functionality
/// - Save project
struct PostScanReviewView: View {
    let project: SurveyProject
    let refinedHeatmapImage: CGImage?
    let bssidTransitions: [BSSIDTransition]

    @State private var selectedVisualization: HeatmapVisualization = .signalStrength
    @State private var currentHeatmapImage: CGImage?
    @State private var mapScale: CGFloat = 1.0
    @State private var mapOffset: CGSize = .zero
    @State private var showVisualizationPicker = false
    @State private var showShareSheet = false
    @State private var showRoamingOverlay = true
    @State private var showWalkingPath = true
    @State private var isSaved = false
    @State private var errorMessage: String?
    @State private var exportImage: UIImage?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Colors.backgroundBase.ignoresSafeArea()

            // Full-screen map with heatmap overlay
            mapContent

            // Floating UI overlays
            VStack {
                // Top bar: stats and overlays
                topBar

                Spacer()

                // Bottom controls: visualization picker + share/save
                bottomControls
            }
        }
        .navigationTitle("Scan Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    saveProject()
                } label: {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .foregroundStyle(isSaved ? Theme.Colors.success : Theme.Colors.accent)
                }
                .accessibilityIdentifier("postScan_button_save")
            }
        }
        .onAppear {
            currentHeatmapImage = refinedHeatmapImage
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $showVisualizationPicker) {
            visualizationPickerSheet
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportImage {
                HeatmapShareSheet(items: [exportImage])
            }
        }
        .accessibilityIdentifier("postScan_screen")
    }

    // MARK: - Map Content

    private var mapContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Floor plan base layer
                if let uiImage = UIImage(data: project.floorPlan.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(mapScale)
                        .offset(mapOffset)
                        .gesture(mapGestures)
                        .accessibilityIdentifier("postScan_floorPlan")
                }

                // Heatmap overlay
                if let heatmapCG = currentHeatmapImage {
                    Image(decorative: heatmapCG, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(0.7)
                        .scaleEffect(mapScale)
                        .offset(mapOffset)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("postScan_heatmapOverlay")
                }

                // AP roaming overlay (P1)
                if showRoamingOverlay && !bssidTransitions.isEmpty {
                    roamingOverlayLayer(in: geometry.size)
                }
            }
        }
    }

    private var mapGestures: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                mapScale = max(0.5, min(8.0, scale))
            }
            .simultaneously(with:
                DragGesture()
                    .onChanged { value in
                        mapOffset = value.translation
                    }
            )
    }

    // MARK: - Roaming Overlay (P1)

    private func roamingOverlayLayer(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            for transition in bssidTransitions {
                // Convert world coordinates to normalized canvas position
                let normalizedX = CGFloat(transition.worldX - mapBoundsMinX) / CGFloat(mapBoundsWidth)
                let normalizedY = CGFloat(transition.worldZ - mapBoundsMinZ) / CGFloat(mapBoundsHeight)

                let x = normalizedX * canvasSize.width
                let y = normalizedY * canvasSize.height

                // Draw a small marker at the roaming boundary
                let markerRect = CGRect(x: x - 6, y: y - 6, width: 12, height: 12)
                context.fill(
                    Path(ellipseIn: markerRect),
                    with: .color(.orange.opacity(0.8))
                )
                context.stroke(
                    Path(ellipseIn: markerRect),
                    with: .color(.white),
                    lineWidth: 1.5
                )
            }
        }
        .scaleEffect(mapScale)
        .offset(mapOffset)
        .allowsHitTesting(false)
        .accessibilityIdentifier("postScan_roamingOverlay")
    }

    private var mapBoundsMinX: Float {
        guard let first = bssidTransitions.first else { return 0 }
        return bssidTransitions.reduce(first.worldX) { min($0, $1.worldX) } - 1
    }

    private var mapBoundsMinZ: Float {
        guard let first = bssidTransitions.first else { return 0 }
        return bssidTransitions.reduce(first.worldZ) { min($0, $1.worldZ) } - 1
    }

    private var mapBoundsWidth: Float {
        guard let first = bssidTransitions.first else { return 1 }
        let maxX = bssidTransitions.reduce(first.worldX) { max($0, $1.worldX) }
        return max(1, maxX - mapBoundsMinX + 2)
    }

    private var mapBoundsHeight: Float {
        guard let first = bssidTransitions.first else { return 1 }
        let maxZ = bssidTransitions.reduce(first.worldZ) { max($0, $1.worldZ) }
        return max(1, maxZ - mapBoundsMinZ + 2)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Coverage percentage
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("\(project.measurementPoints.count) pts")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("postScan_stats_pointCount")

            // AP roaming toggle
            if !bssidTransitions.isEmpty {
                Button {
                    showRoamingOverlay.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption2)
                        Text("Roaming")
                            .font(.caption2)
                    }
                    .foregroundStyle(showRoamingOverlay ? .orange : .white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityIdentifier("postScan_button_roamingToggle")
            }

            Spacer()

            // Survey mode badge
            Text("Continuous")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier("postScan_badge_surveyMode")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Visualization picker button
            Button {
                showVisualizationPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: visualizationIcon)
                        .font(.caption.weight(.semibold))
                    Text(visualizationLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityIdentifier("postScan_button_visualizationPicker")

            // Share/export button
            HStack(spacing: 16) {
                Button {
                    exportAndShare()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                        Text("Share")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                            .fill(Theme.Colors.accent.opacity(0.8))
                    )
                }
                .accessibilityIdentifier("postScan_button_share")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Visualization Helpers

    private var visualizationIcon: String {
        switch selectedVisualization {
        case .signalStrength: return "wifi"
        case .signalToNoise: return "waveform.path"
        case .downloadSpeed: return "arrow.down.circle"
        case .uploadSpeed: return "arrow.up.circle"
        case .latency: return "clock"
        }
    }

    private var visualizationLabel: String {
        switch selectedVisualization {
        case .signalStrength: return "Signal Strength"
        case .signalToNoise: return "Signal-to-Noise"
        case .downloadSpeed: return "Download Speed"
        case .uploadSpeed: return "Upload Speed"
        case .latency: return "Latency"
        }
    }

    // MARK: - Visualization Picker Sheet

    private var visualizationPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(HeatmapVisualization.allCases, id: \.self) { viz in
                    Button {
                        switchVisualization(to: viz)
                        showVisualizationPicker = false
                    } label: {
                        HStack {
                            Label(
                                labelForVisualization(viz),
                                systemImage: iconForVisualization(viz)
                            )
                            .foregroundStyle(Theme.Colors.textPrimary)

                            Spacer()

                            if viz == selectedVisualization {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                    .accessibilityIdentifier("postScan_viz_\(viz)")
                }
            }
            .navigationTitle("Visualization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showVisualizationPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("postScan_vizPicker_sheet")
    }

    private func labelForVisualization(_ viz: HeatmapVisualization) -> String {
        switch viz {
        case .signalStrength: return "Signal Strength"
        case .signalToNoise: return "Signal-to-Noise Ratio"
        case .downloadSpeed: return "Download Speed"
        case .uploadSpeed: return "Upload Speed"
        case .latency: return "Latency"
        }
    }

    private func iconForVisualization(_ viz: HeatmapVisualization) -> String {
        switch viz {
        case .signalStrength: return "wifi"
        case .signalToNoise: return "waveform.path"
        case .downloadSpeed: return "arrow.down.circle"
        case .uploadSpeed: return "arrow.up.circle"
        case .latency: return "clock"
        }
    }

    // MARK: - Visualization Switching

    private func switchVisualization(to type: HeatmapVisualization) {
        selectedVisualization = type
        guard project.measurementPoints.count >= 3 else { return }

        currentHeatmapImage = HeatmapRenderer.render(
            points: project.measurementPoints,
            floorPlanWidth: project.floorPlan.pixelWidth,
            floorPlanHeight: project.floorPlan.pixelHeight,
            visualization: type,
            colorScheme: .wifiman
        )
    }

    // MARK: - Save

    private func saveProject() {
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let safeName = project.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = safeName.isEmpty ? "Untitled" : safeName
        let bundleURL = documentsURL.appendingPathComponent("\(fileName).netmonsurvey")

        do {
            try SurveyFileManager.save(project, to: bundleURL)
            isSaved = true
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    // MARK: - Export/Share

    private func exportAndShare() {
        // Render the current visualization as an image for sharing
        guard let floorPlanImage = UIImage(data: project.floorPlan.imageData)
        else {
            errorMessage = "Unable to generate export image."
            return
        }

        // Compose floor plan + heatmap overlay
        let size = floorPlanImage.size
        let renderer = UIGraphicsImageRenderer(size: size)
        let composited = renderer.image { _ in
            floorPlanImage.draw(in: CGRect(origin: .zero, size: size))

            if let heatmapCG = currentHeatmapImage {
                let heatmapUI = UIImage(cgImage: heatmapCG)
                heatmapUI.draw(
                    in: CGRect(origin: .zero, size: size),
                    blendMode: .normal,
                    alpha: 0.7
                )
            }
        }

        exportImage = composited
        showShareSheet = true
    }
}

// MARK: - HeatmapShareSheet

/// UIActivityViewController wrapper for sharing heatmap content.
private struct HeatmapShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    let project = SurveyProject(
        name: "Test Scan",
        floorPlan: FloorPlan(
            imageData: Data(),
            widthMeters: 10.0,
            heightMeters: 8.0,
            pixelWidth: 512,
            pixelHeight: 512,
            origin: .arGenerated
        ),
        measurementPoints: [],
        surveyMode: .arContinuous
    )

    NavigationStack {
        PostScanReviewView(
            project: project,
            refinedHeatmapImage: nil,
            bssidTransitions: []
        )
    }
}
