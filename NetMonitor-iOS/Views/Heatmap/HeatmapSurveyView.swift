import NetMonitorCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - HeatmapSurveyView

struct HeatmapSurveyView: View {
    @Environment(DeepLinkRouter.self) private var deepLinkRouter: DeepLinkRouter?
    @State private var viewModel = HeatmapSurveyViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showImportOptions = false
    @State private var showRoomScanner = false
    @State private var showShareSheet = false
    @State private var showProjectsList = false
    @State private var shareItems: [Any] = []
    @State private var showShortcutSetup = false
    @State private var shortcutsProvider = ShortcutsWiFiProvider()

    var body: some View {
        ZStack {
            if viewModel.hasFloorPlan {
                surveyContent
            } else {
                startContent
            }
        }
        .themedBackground()
        .navigationTitle("Wi-Fi Heatmap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar { toolbarContent }
        .confirmationDialog("Import Floor Plan", isPresented: $showImportOptions) {
            Button("Choose from Photos") {
                viewModel.showPhotoPicker = true
            }
            .accessibilityIdentifier("heatmap_button_choosePhoto")
            Button("Choose from Files") {
                viewModel.showImportSheet = true
            }
            .accessibilityIdentifier("heatmap_button_chooseFile")
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $viewModel.showImportSheet,
            allowedContentTypes: [.png, .jpeg, .heic, netmonSurveyType, netmonBlueprintType],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .photosPicker(
            isPresented: $viewModel.showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task<Void, Never> {
                await handlePhotoImport(newItem)
            }
            selectedPhotoItem = nil
        }
        .sheet(isPresented: $viewModel.showCalibrationSheet) {
            HeatmapCalibrationSheet(viewModel: viewModel)
                .accessibilityIdentifier("heatmap_sheet_calibration")
        }
        .sheet(isPresented: $showRoomScanner) {
            NavigationStack {
                RoomPlanScannerView { blueprint in
                    viewModel.importBlueprintProject(blueprint)
                }
            }
            .accessibilityIdentifier("heatmap_sheet_roomScanner")
        }
        .sheet(isPresented: $showShareSheet) {
            if !shareItems.isEmpty {
                ShareSheet(activityItems: shareItems)
                    .accessibilityIdentifier("heatmap_sheet_share")
            }
        }
        .sheet(isPresented: $showProjectsList) {
            HeatmapProjectsView { url in
                openFileFromDeepLink(url)
            }
            .accessibilityIdentifier("heatmap_sheet_projects")
        }
        .sheet(isPresented: $showShortcutSetup) {
            WiFiShortcutSetupView(
                shortcutsProvider: shortcutsProvider,
                onDismiss: { showShortcutSetup = false },
                onSkip: { showShortcutSetup = false }
            )
            .accessibilityIdentifier("heatmap_sheet_shortcutSetup")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .accessibilityIdentifier("screen_heatmapSurvey")
        .onAppear {
            // Check if a .netmonsurvey file was opened via deep link
            if let url = deepLinkRouter?.consumePendingFile() {
                openFileFromDeepLink(url)
            }
            // Check if shortcut setup should be shown
            Task<Void, Never> {
                let hasSeen = UserDefaults.standard.bool(forAppKey: AppSettings.Keys.hasSeenShortcutSetup)
                if !hasSeen {
                    let available = await shortcutsProvider.checkAvailability()
                    if !available {
                        showShortcutSetup = true
                    }
                }
            }
        }
        .onChange(of: deepLinkRouter?.pendingSurveyFileURL) { _, newURL in
            if newURL != nil, let url = deepLinkRouter?.consumePendingFile() {
                openFileFromDeepLink(url)
            }
        }
    }

    // MARK: - UTTypes

    private var netmonSurveyType: UTType {
        UTType("com.netmonitor.survey") ?? .data
    }

    private var netmonBlueprintType: UTType {
        UTType("com.netmonitor.blueprint") ?? .data
    }

    // MARK: - Start Content

    private var startContent: some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            Spacer()

            Image(systemName: "wifi.circle")
                .font(.system(size: 72))
                .foregroundStyle(Theme.Colors.textSecondary)
                .symbolEffect(.pulse, options: .repeating)

            Text("Wi-Fi Heatmap")
                .font(.title2.bold())
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Map your Wi-Fi signal strength\nacross any space")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: Theme.Layout.itemSpacing) {
                HStack(spacing: Theme.Layout.itemSpacing) {
                    startCard(
                        icon: "photo.on.rectangle",
                        title: "Import\nFloor Plan",
                        identifier: "heatmap_button_import"
                    ) {
                        showImportOptions = true
                    }

                    startCard(
                        icon: "camera.viewfinder",
                        title: "Scan\nRoom",
                        identifier: "heatmap_button_scanroom"
                    ) {
                        showRoomScanner = true
                    }
                }

                Button {
                    openSurvey()
                } label: {
                    Label("Open Saved Survey", systemImage: "folder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .glassCard(cornerRadius: Theme.Layout.buttonCornerRadius, padding: 0)
                .accessibilityIdentifier("heatmap_button_opensurvey")
            }
            .padding(.horizontal, Theme.Layout.screenPadding)

            Spacer()
        }
    }

    private func startCard(
        icon: String,
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.Colors.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .glassCard(cornerRadius: Theme.Layout.cardCornerRadius, padding: Theme.Layout.cardPadding)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Survey Content

    private var surveyContent: some View {
        ZStack(alignment: .bottom) {
            // Canvas layer
            HeatmapCanvasView(viewModel: viewModel)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityIdentifier("heatmap_canvas_floorplan")

            // Floating HUD
            VStack {
                signalHUD
                    .padding(.horizontal, Theme.Layout.screenPadding)
                    .padding(.top, 8)
                Spacer()
            }

            // Bottom sheet
            HeatmapSidebarSheet(
                viewModel: viewModel,
                shortcutsProvider: shortcutsProvider,
                onShare: { shareHeatmap() },
                onSetup: { showShortcutSetup = true }
            )
        }
    }

    // MARK: - Signal HUD

    private var signalHUD: some View {
        HStack(spacing: 16) {
            // Live RSSI with color
            HStack(spacing: 6) {
                if shortcutsProvider.isAvailable {
                    Image(systemName: rssiWiFiIcon(viewModel.currentRSSI))
                        .font(.caption.bold())
                        .foregroundStyle(rssiColor(viewModel.currentRSSI))
                    Text("\(viewModel.currentRSSI) dBm")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Theme.Colors.textPrimary)
                } else {
                    Image(systemName: "wifi.slash")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("No Signal Data")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .accessibilityIdentifier("heatmap_hud_rssi")

            Divider()
                .frame(height: 16)

            // SSID
            Text(viewModel.currentSSID ?? "No WiFi")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .accessibilityIdentifier("heatmap_hud_ssid")

            Divider()
                .frame(height: 16)

            // Point count
            HStack(spacing: 2) {
                Text("\(viewModel.measurementPoints.count)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("pts")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityIdentifier("heatmap_hud_pointcount")

            // Save indicator
            if viewModel.isSaving {
                ProgressView()
                    .scaleEffect(0.5)
            } else if let lastSave = viewModel.lastSaveDate {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.success)
                    .help("Last saved \(lastSave.formatted(.relative(presentation: .numeric)))")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 24, padding: 0)
        .accessibilityIdentifier("heatmap_hud_signal")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if viewModel.hasFloorPlan {
                // Share
                Button {
                    shareHeatmap()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.measurementPoints.isEmpty)
                .accessibilityIdentifier("heatmap_button_share")

                // More menu
                Menu {
                    Button {
                        showImportOptions = true
                    } label: {
                        Label("Import Floor Plan", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("heatmap_button_importNew")

                    Button {
                        openSurvey()
                    } label: {
                        Label("Open Survey", systemImage: "folder")
                    }
                    .accessibilityIdentifier("heatmap_button_openSurveyMenu")

                    Divider()

                    Button {
                        saveSurvey()
                    } label: {
                        Label("Save Project", systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.surveyProject == nil)
                    .accessibilityIdentifier("heatmap_button_save")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("heatmap_menu_more")
            }
        }
    }

    // MARK: - File Handling

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                if url.pathExtension == "netmonblueprint" {
                    try viewModel.importBlueprint(from: url)
                } else if url.pathExtension == "netmonsurvey" {
                    try viewModel.loadProject(from: url)
                } else {
                    try viewModel.importFloorPlan(from: url)
                }
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func handlePhotoImport(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            viewModel.errorMessage = "Failed to load photo"
            return
        }
        do {
            try viewModel.importFloorPlan(imageData: data, name: "Photo Import")
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func openFileFromDeepLink(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            if url.pathExtension == "netmonblueprint" {
                try viewModel.importBlueprint(from: url)
            } else {
                try viewModel.loadProject(from: url)
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func openSurvey() {
        showProjectsList = true
    }

    private func saveSurvey() {
        guard let project = viewModel.surveyProject else { return }
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let saveURL = documentsURL?.appendingPathComponent("\(project.name).netmonsurvey") else { return }
        do {
            try viewModel.saveProject(to: saveURL)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func shareHeatmap() {
        var items: [Any] = []

        // PNG image export
        if let image = viewModel.exportImage(canvasSize: CGSize(width: 1024, height: 768)) {
            items.append(image)
        }

        // .netmonsurvey file export
        if let projectURL = viewModel.exportProjectFile() {
            items.append(projectURL)
        }

        guard !items.isEmpty else { return }
        shareItems = items
        showShareSheet = true
    }

    // MARK: - Helpers

    private func rssiColor(_ rssi: Int) -> Color {
        switch rssi {
        case -50...0: .green
        case -60 ..< -50: .yellow
        case -70 ..< -60: .orange
        default: .red
        }
    }

    private func rssiWiFiIcon(_ rssi: Int) -> String {
        switch rssi {
        case -50...0: "wifi"
        case -60 ..< -50: "wifi"
        case -70 ..< -60: "wifi.exclamationmark"
        default: "wifi.slash"
        }
    }
}
