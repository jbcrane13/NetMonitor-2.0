import SwiftUI
import PhotosUI
import NetMonitorCore

// MARK: - WiFiHeatmapSurveyView

struct WiFiHeatmapSurveyView: View {
    @State private var viewModel = WiFiHeatmapSurveyViewModel()
    @State private var showingGuide = false
    @State private var showingFullScreen = false
    @State private var showingCalibration = false
    @State private var selectedPhoto: PhotosPickerItem?
    // Local binding-compatible mirror for HeatmapFullScreenView (which requires @Binding)
    @State private var fullScreenPoints: [HeatmapDataPoint] = []

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                statusBarSection
                heatmapCanvasSection
                HeatmapControlStrip(
                    colorScheme: $viewModel.colorScheme,
                    overlays: $viewModel.displayOverlays,
                    isSurveying: viewModel.isSurveying,
                    onStopSurvey: { viewModel.stopSurvey() }
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
                actionButtonsSection
                MeasurementsPanel(
                    points: viewModel.dataPoints,
                    isSurveying: viewModel.isSurveying,
                    calibration: viewModel.calibration,
                    preferredUnit: $viewModel.preferredUnit
                )
                if !viewModel.surveys.isEmpty {
                    previousSurveysSection
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("WiFi Heatmap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingGuide = true } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityIdentifier("heatmap_button_info")
            }
        }
        .sheet(isPresented: $showingGuide) { guideSheet }
        .sheet(isPresented: $showingCalibration) {
            CalibrationView(
                floorplanImage: viewModel.floorplanImageData.flatMap(UIImage.init),
                onComplete: { scale in
                    if let scale {
                        viewModel.setCalibration(pixelDist: scale.pixelDistance,
                                                 realDist: scale.realDistance,
                                                 unit: scale.unit)
                    }
                    showingCalibration = false
                }
            )
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            HeatmapFullScreenView(
                points: $fullScreenPoints,
                floorplanImage: viewModel.floorplanImageData.flatMap(UIImage.init),
                colorScheme: $viewModel.colorScheme,
                overlays: $viewModel.displayOverlays,
                calibration: viewModel.calibration,
                isSurveying: viewModel.isSurveying,
                onTap: { loc, size in viewModel.recordDataPoint(at: loc, in: size) },
                onStopSurvey: { viewModel.stopSurvey() },
                onDismiss: { showingFullScreen = false }
            )
        }
        .onChange(of: viewModel.dataPoints.count) { _, _ in
            fullScreenPoints = viewModel.dataPoints
        }
        .onAppear {
            fullScreenPoints = viewModel.dataPoints
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    viewModel.floorplanImageData = data
                    viewModel.selectedMode = .floorplan
                    showingCalibration = true
                }
            }
        }
        .accessibilityIdentifier("screen_wifiHeatmapTool")
    }

    // MARK: - Status Bar

    private var statusBarSection: some View {
        GlassCard {
            HStack(spacing: Theme.Layout.itemSpacing) {
                Image(systemName: "wifi.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.isSurveying ? viewModel.signalColor : Theme.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isSurveying ? "Recording" : "Ready")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if viewModel.calibration != nil {
                    Label("Calibrated", systemImage: "ruler")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.accent.opacity(0.1))
                        .clipShape(Capsule())
                }

                if viewModel.isSurveying {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.signalText)
                            .font(.headline).fontWeight(.bold)
                            .foregroundStyle(viewModel.signalColor)
                            .monospacedDigit()
                        Text(viewModel.signalLevel.label)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("heatmap_status_bar")
    }

    // MARK: - Canvas

    private var heatmapCanvasSection: some View {
        ZStack {
            HeatmapCanvasView(
                points: viewModel.dataPoints,
                floorplanImage: viewModel.floorplanImageData.flatMap(UIImage.init),
                colorScheme: viewModel.colorScheme,
                overlays: viewModel.displayOverlays,
                calibration: viewModel.calibration,
                isSurveying: viewModel.isSurveying,
                onTap: { loc, size in viewModel.recordDataPoint(at: loc, in: size) }
            )
            .frame(height: 280)

            // Full-screen button
            Button {
                showingFullScreen = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(10)
            .accessibilityIdentifier("heatmap_button_fullscreen")
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            Button {
                if viewModel.isSurveying { viewModel.stopSurvey() }
                else { viewModel.startSurvey() }
            } label: {
                HStack {
                    Image(systemName: viewModel.isSurveying ? "record.circle" : "play.circle.fill")
                    Text(viewModel.isSurveying ? "Recording…" : "Start Survey")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.isSurveying ? Theme.Colors.warning : Theme.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
            }
            .accessibilityIdentifier("heatmap_button_main_action")

            HStack(spacing: Theme.Layout.itemSpacing) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text("Floor Plan")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
                    .foregroundStyle(Theme.Colors.textPrimary)
                }
                .accessibilityIdentifier("heatmap_button_select_floorplan")

                Button {
                    showingCalibration = true
                } label: {
                    HStack {
                        Image(systemName: "ruler")
                        Text("Calibrate")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(viewModel.calibration != nil
                                ? Theme.Colors.accent.opacity(0.12)
                                : Color.clear.opacity(0))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
                    .foregroundStyle(viewModel.calibration != nil ? Theme.Colors.accent : Theme.Colors.textPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                            .stroke(viewModel.calibration != nil ? Theme.Colors.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                }
                .accessibilityIdentifier("heatmap_button_calibrate")
            }
        }
    }

    // MARK: - Previous Surveys

    private var previousSurveysSection: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Saved Surveys")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(viewModel.surveys) { survey in
                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(survey.name)
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                if survey.calibration != nil {
                                    Label("", systemImage: "ruler")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            Text("\(survey.dataPoints.count) points • \(survey.mode.displayName)")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(survey.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Spacer()
                        Button { viewModel.deleteSurvey(survey) } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.Colors.error)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Guide Sheet

    private var guideSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                    guideSection(icon: "ruler", title: "Calibration",
                        body: "After importing a floor plan, draw a line between two known points and enter the real distance. This unlocks real-world measurements.")
                    guideSection(icon: "hand.tap", title: "Survey",
                        body: "Start a survey, walk to each location, and tap the canvas to record the WiFi signal at that spot.")
                    guideSection(icon: "thermometer.medium", title: "Color Schemes",
                        body: "Thermal (default): blue → red by signal strength. Signal: red → green. Nebula and Arctic for stylised views.")
                    guideSection(icon: "exclamationmark.triangle", title: "Permissions",
                        body: "Live signal readings require the Wi-Fi Info entitlement. Without it, the app uses simulated values for demonstration.")
                }
                .padding(Theme.Layout.screenPadding)
            }
            .themedBackground()
            .navigationTitle("Heatmap Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingGuide = false }
                        .fontWeight(.semibold).foregroundStyle(Theme.Colors.accent)
                        .accessibilityIdentifier("heatmap_button_guide_done")
                }
            }
        }
        .accessibilityIdentifier("screen_wifiHeatmapGuide")
    }

    private func guideSection(icon: String, title: String, body: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: Theme.Layout.itemSpacing) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.Colors.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.Colors.textPrimary)
                    Text(body).font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack { WiFiHeatmapSurveyView() }
}
