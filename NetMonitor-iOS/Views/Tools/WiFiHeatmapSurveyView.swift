import SwiftUI
import PhotosUI
import NetMonitorCore

// MARK: - WiFiHeatmapSurveyView

struct WiFiHeatmapSurveyView: View {
    @State private var viewModel = WiFiHeatmapSurveyViewModel()
    @State private var showingGuide = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                statusBarSection
                modePickerSection
                heatmapCanvasSection
                actionButtonsSection
                if viewModel.isSurveying {
                    measurementSection
                }
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
                Button {
                    showingGuide = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityIdentifier("heatmap_button_info")
            }
        }
        .sheet(isPresented: $showingGuide) {
            guideSheet
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    viewModel.floorplanImageData = data
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
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if viewModel.isSurveying {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.signalText)
                            .font(.headline)
                            .fontWeight(.bold)
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

    // MARK: - Mode Picker

    private var modePickerSection: some View {
        Picker("Mode", selection: $viewModel.selectedMode) {
            ForEach(HeatmapMode.allCases, id: \.self) { mode in
                Label(mode.displayName, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("heatmap_picker_mode")
    }

    // MARK: - Canvas

    private var heatmapCanvasSection: some View {
        GlassCard(padding: 0) {
            GeometryReader { geo in
                ZStack {
                    // Floor plan background (if floorplan mode + image loaded)
                    if viewModel.selectedMode == .floorplan,
                       let data = viewModel.floorplanImageData,
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .opacity(0.6)
                    } else {
                        // Grid background
                        gridBackground(in: geo.size)
                    }

                    // Heatmap dots
                    let points = viewModel.dataPoints
                    Canvas { context, size in
                        for point in points {
                            let x = point.x * size.width
                            let y = point.y * size.height
                            let level = SignalLevel.from(rssi: point.signalStrength)
                            let color: SwiftUI.Color = {
                                switch level {
                                case .strong: return .green
                                case .fair:   return .yellow
                                case .weak:   return .red
                                }
                            }()
                            let rect = CGRect(x: x - 12, y: y - 12, width: 24, height: 24)
                            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.75)))
                            context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.5)), lineWidth: 1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Invisible tap target when surveying
                    if viewModel.isSurveying {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                viewModel.recordDataPoint(at: location, in: geo.size)
                            }
                    }
                }
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, new in canvasSize = new }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
        }
    }

    @ViewBuilder
    private func gridBackground(in size: CGSize) -> some View {
        Canvas { context, size in
            let step: CGFloat = 40
            var x: CGFloat = 0
            while x <= size.width {
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                    with: .color(.white.opacity(0.05)), lineWidth: 0.5
                )
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                    with: .color(.white.opacity(0.05)), lineWidth: 0.5
                )
                y += step
            }
        }
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            // Main action button
            Button {
                if viewModel.isSurveying {
                    viewModel.stopSurvey()
                } else {
                    viewModel.startSurvey()
                }
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
                // Select floor plan
                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images
                ) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text("Select Floor Plan")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
                    .foregroundStyle(Theme.Colors.textPrimary)
                }
                .accessibilityIdentifier("heatmap_button_select_floorplan")

                // Survey without floor plan
                Button {
                    viewModel.selectedMode = .freeform
                    viewModel.floorplanImageData = nil
                    if !viewModel.isSurveying { viewModel.startSurvey() }
                } label: {
                    HStack {
                        Image(systemName: "hand.tap")
                        Text("Freeform Survey")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
                    .foregroundStyle(Theme.Colors.textPrimary)
                }
                .accessibilityIdentifier("heatmap_button_survey_without_floorplan")
            }
        }
    }

    // MARK: - Measurement Section (shown during survey)

    private var measurementSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                HStack {
                    Text("Measurements")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer()

                    Button {
                        viewModel.stopSurvey()
                    } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.error)
                    }
                    .accessibilityIdentifier("heatmap_button_stop")
                }

                if viewModel.dataPoints.isEmpty {
                    Text("Tap the canvas above to record signal at each location")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("\(viewModel.dataPoints.count) points recorded")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    // Signal legend
                    HStack(spacing: 16) {
                        signalLegendItem(color: .green, label: "Strong (≥-50)")
                        signalLegendItem(color: .yellow, label: "Fair (-70–-50)")
                        signalLegendItem(color: .red, label: "Weak (<-70)")
                    }
                    .font(.caption2)
                }
            }
        }
        .accessibilityIdentifier("heatmap_section_measurement")
    }

    private func signalLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(Theme.Colors.textSecondary)
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
                            Text(survey.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("\(survey.dataPoints.count) points • \(survey.mode.displayName)")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(survey.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Spacer()
                        Button {
                            viewModel.deleteSurvey(survey)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Theme.Colors.error)
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
                    guideSection(
                        icon: "hand.tap",
                        title: "Freeform Mode",
                        body: "Walk around your space and tap the canvas to record WiFi signal strength at each location. Points are colored by signal quality."
                    )
                    guideSection(
                        icon: "map",
                        title: "Floorplan Mode",
                        body: "Import an image of your floor plan, then tap on the map while walking to each location. This provides a visual reference for coverage gaps."
                    )
                    guideSection(
                        icon: "circle.fill",
                        title: "Reading the Heatmap",
                        body: "🟢 Green = Strong signal (≥ -50 dBm)\n🟡 Yellow = Fair signal (-70 to -50 dBm)\n🔴 Red = Weak signal (< -70 dBm)"
                    )
                    guideSection(
                        icon: "exclamationmark.triangle",
                        title: "Permissions Note",
                        body: "Live signal readings require the Wi-Fi Info entitlement. Without it, the app uses simulated values for demonstration."
                    )
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
                    Button("Done") {
                        showingGuide = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityIdentifier("heatmap_button_guide_done")
                }
            }
        }
        .accessibilityIdentifier("screen_wifiHeatmapGuide")
    }

    private func guideSection(icon: String, title: String, body: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: Theme.Layout.itemSpacing) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack {
        WiFiHeatmapSurveyView()
    }
}
