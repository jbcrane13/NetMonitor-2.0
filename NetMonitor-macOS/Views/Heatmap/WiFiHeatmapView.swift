import NetMonitorCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - WiFiHeatmapView

struct WiFiHeatmapView: View {
    var pendingSurveyURL: URL? = nil

    @State private var viewModel = WiFiHeatmapViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showImportOptions = false
    @State private var showBlueprintImporter = false

    var body: some View {
        HSplitView {
            if !viewModel.isSidebarCollapsed {
                HeatmapSidebarView(viewModel: viewModel)
            }
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { toolbarContent }
        .confirmationDialog("Import Floor Plan", isPresented: $showImportOptions) {
            Button("Choose Image File…") {
                viewModel.showImportSheet = true
            }
            .accessibilityIdentifier("heatmap_button_chooseFile")
            Button("Choose from Photos…") {
                viewModel.showPhotoPicker = true
            }
            .accessibilityIdentifier("heatmap_button_choosePhoto")
            Button("Import Blueprint (.netmonblueprint)…") {
                showBlueprintImporter = true
            }
            .accessibilityIdentifier("heatmap_button_importBlueprint")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("heatmap_button_dialogCancel")
        }
        .fileImporters(
            showImportSheet: $viewModel.showImportSheet,
            showBlueprintImporter: $showBlueprintImporter,
            onFileImport: handleFileImport,
            onBlueprintImport: handleBlueprintImport
        )
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
            CalibrationSheet(viewModel: viewModel)
        }
        .onOpenURL { url in
            if url.pathExtension == "netmonblueprint" {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    try viewModel.importBlueprint(from: url)
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
        .onChange(of: pendingSurveyURL) { _, newURL in
            guard let newURL else { return }
            let didAccess = newURL.startAccessingSecurityScopedResource()
            defer { if didAccess { newURL.stopAccessingSecurityScopedResource() } }
            do {
                try viewModel.importBlueprint(from: newURL)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .onAppear {
            // Handle pendingSurveyURL passed from ContentView on first appear
            if let url = pendingSurveyURL {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    try viewModel.importBlueprint(from: url)
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            viewModel.onAppear()
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
                .accessibilityIdentifier("heatmap_button_dismissError")
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityIdentifier("screen_heatmap")
    }

    // MARK: - Canvas

    private var canvas: some View {
        Group {
            if viewModel.surveyProject != nil {
                HeatmapCanvasRepresentable(
                    floorPlanImageData: viewModel.surveyProject?.floorPlan.imageData,
                    measurementPoints: viewModel.filteredPoints,
                    calibrationPoints: viewModel.calibrationPoints,
                    isCalibrating: viewModel.isCalibrating,
                    isSurveying: viewModel.isSurveying,
                    isMeasuring: viewModel.isMeasuring,
                    pendingMeasurementLocation: viewModel.pendingMeasurementLocation,
                    heatmapCGImage: viewModel.heatmapCGImage,
                    overlayOpacity: viewModel.overlayOpacity,
                    coverageThreshold: viewModel.isCoverageThresholdEnabled ? viewModel.coverageThreshold : nil,
                    onTap: { normalizedPoint in
                        if viewModel.isCalibrating {
                            viewModel.addCalibrationPoint(at: normalizedPoint)
                        } else if viewModel.isSurveying {
                            Task<Void, Never> {
                                await viewModel.takeMeasurement(at: normalizedPoint)
                            }
                        }
                    },
                    onPointDelete: { pointId in
                        viewModel.deletePoint(id: pointId)
                    },
                    onHover: { point in
                        viewModel.updateCursorLocation(point)
                    }
                )
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("WiFi Heatmap")
                .font(.title2)
            Text("Import a floor plan image to start surveying WiFi coverage")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Import Floor Plan") {
                    showImportOptions = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("heatmap_button_import")

                Button("Import Blueprint") {
                    importBlueprint()
                }
                .accessibilityIdentifier("heatmap_button_importBlueprint")

                Button("Open Project") {
                    loadProject()
                }
                .accessibilityIdentifier("heatmap_button_open")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Toolbar

    // MARK: - File Handling

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                try viewModel.importFloorPlan(from: url)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func handleBlueprintImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                try viewModel.importBlueprint(from: url)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func handlePhotoImport(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let name = "Photo Import"
        do {
            try viewModel.importFloorPlan(imageData: data, name: name)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func saveProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "netmonsurvey")].compactMap { $0 }
        panel.nameFieldStringValue = viewModel.surveyProject?.name ?? "Survey"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try viewModel.saveProject(to: url)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func loadProject() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
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
    }

    private func importBlueprint() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a .netmonblueprint file exported from the iOS Room Scanner"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try viewModel.importBlueprint(from: url)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func exportImage() {
        guard let data = viewModel.exportPNG(canvasSize: CGSize(width: 800, height: 600)) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(viewModel.surveyProject?.name ?? "heatmap")-export"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func exportPDF() {
        guard let pdfData = viewModel.exportPDF() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(viewModel.surveyProject?.name ?? "heatmap")-report"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try pdfData.write(to: url)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - WiFiHeatmapView Toolbar

extension WiFiHeatmapView {
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Project name
            if let name = viewModel.surveyProject?.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Visualization picker (toolbar)
            if viewModel.surveyProject != nil {
                let pts = viewModel.filteredPoints
                Picker("Viz", selection: $viewModel.selectedVisualization) {
                    ForEach(HeatmapVisualization.allCases, id: \.self) { viz in
                        Text(viz.displayName + (viz.hasData(in: pts) ? "" : " (no data)"))
                            .tag(viz)
                    }
                }
                .frame(width: 140)
                .onChange(of: viewModel.selectedVisualization) { _, _ in
                    if viewModel.isHeatmapGenerated { viewModel.generateHeatmap() }
                }
                .accessibilityIdentifier("heatmap_picker_viz")

                if !pts.isEmpty {
                    Text("\(pts.count) pts")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Point count (fallback for when no project)
            if viewModel.surveyProject == nil, !viewModel.measurementPoints.isEmpty {
                Text("\(viewModel.filteredPoints.count) pts")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Import
            Button {
                showImportOptions = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("heatmap_button_import")

            // Calibrate
            if viewModel.isCalibrating {
                Button {
                    viewModel.cancelCalibration()
                } label: {
                    Label("Cancel Calibration", systemImage: "xmark")
                }
                .accessibilityIdentifier("heatmap_button_cancelCalibrationToolbar")
            } else {
                Button {
                    viewModel.startCalibration()
                } label: {
                    Label("Calibrate", systemImage: "ruler")
                }
                .disabled(viewModel.surveyProject == nil)
                .accessibilityIdentifier("heatmap_button_calibrate")
            }

            // Save
            Button { saveProject() } label: {
                Label("Save", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.surveyProject == nil)
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityIdentifier("heatmap_button_save")

            // Open
            Button { loadProject() } label: {
                Label("Open", systemImage: "folder")
            }
            .accessibilityIdentifier("heatmap_button_open")

            // Export
            Menu {
                Button("Export PNG") { exportImage() }
                    .accessibilityIdentifier("heatmap_button_exportPNG")
                Button("Export PDF") { exportPDF() }
                    .accessibilityIdentifier("heatmap_button_exportPDF")
            } label: {
                Label("Export", systemImage: "doc.richtext")
            }
            .disabled(viewModel.surveyProject == nil || viewModel.measurementPoints.isEmpty)
            .accessibilityIdentifier("heatmap_button_export")

            // Undo
            Button {
                viewModel.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityIdentifier("heatmap_button_undo")

            // Sidebar toggle
            Button {
                viewModel.isSidebarCollapsed.toggle()
            } label: {
                Label("Sidebar", systemImage: viewModel.isSidebarCollapsed ? "sidebar.left" : "sidebar.left")
            }
            .accessibilityIdentifier("heatmap_button_sidebar")
        }
    }
}

// MARK: - CalibrationSheet

struct CalibrationSheet: View {
    @Bindable var viewModel: WiFiHeatmapViewModel
    @State private var distanceText: String = "5.0"
    @State private var unit: String = "meters"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Calibrate Floor Plan Scale")
                .font(.headline)

            Text("Click two points on the floor plan with a known distance between them.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.calibrationPoints.count < 2 {
                HStack {
                    Image(systemName: "hand.tap")
                    Text("Click \(2 - viewModel.calibrationPoints.count) more point\(viewModel.calibrationPoints.count == 1 ? "" : "s") on the floor plan")
                }
                .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Known Distance")
                    .font(.subheadline)
                HStack {
                    TextField("Distance", text: $distanceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .accessibilityIdentifier("heatmap_textfield_calibrationDistance")
                    Picker("Unit", selection: $unit) {
                        Text("meters").tag("meters")
                        Text("feet").tag("feet")
                    }
                    .frame(width: 100)
                    .accessibilityIdentifier("heatmap_picker_calibrationUnit")
                }
            }

            if viewModel.calibrationPoints.count == 2 {
                Divider()
                let dist = Double(distanceText) ?? 5.0
                let realDist = unit == "feet" ? dist * 0.3048 : dist
                let metersPerPixel = CalibrationPoint.metersPerPixel(
                    pointA: viewModel.calibrationPoints[0],
                    pointB: viewModel.calibrationPoints[1],
                    knownDistanceMeters: realDist
                )
                if let project = viewModel.surveyProject {
// swiftlint:disable:next identifier_name
                    let w = Double(project.floorPlan.pixelWidth) * metersPerPixel
// swiftlint:disable:next identifier_name
                    let h = Double(project.floorPlan.pixelHeight) * metersPerPixel
                    LabeledContent("Floor plan size:") {
                        Text(String(format: "%.1f × %.1f m", w, h))
                    }
                    .font(.caption)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    viewModel.cancelCalibration()
                    dismiss()
                }
                .accessibilityIdentifier("heatmap_button_cancelCalibration")
                Spacer()
                Button("Save Calibration") {
                    if let dist = Double(distanceText) {
                        let realDist = unit == "feet" ? dist * 0.3048 : dist
                        viewModel.completeCalibration(withDistance: realDist)
                        dismiss()
                    }
                }
                .disabled(viewModel.calibrationPoints.count < 2 || Double(distanceText) == nil)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("heatmap_button_saveCalibration")
            }
        }
        .padding()
        .frame(width: 340, height: 320)
    }
}

// MARK: - File Importers ViewModifier

private enum HeatmapImportContentTypes {
    static let blueprint: [UTType] = {
        let appSpecificType = UTType("com.netmonitor.blueprint")
        let extensionType = UTType(filenameExtension: "netmonblueprint")

#if DEBUG
        if appSpecificType == nil, extensionType == nil {
            assertionFailure("Unable to resolve blueprint UTType. Falling back to ZIP-only import support.")
        }
#endif

        return [appSpecificType, extensionType, .zip].compactMap { $0 }
    }()
}

private extension View {
    func fileImporters(
        showImportSheet: Binding<Bool>,
        showBlueprintImporter: Binding<Bool>,
        onFileImport: @escaping (Result<[URL], Error>) -> Void,
        onBlueprintImport: @escaping (Result<[URL], Error>) -> Void
    ) -> some View {
        self
            .fileImporter(
                isPresented: showImportSheet,
                allowedContentTypes: [.png, .jpeg, .pdf, .heic],
                allowsMultipleSelection: false
            ) { result in
                onFileImport(result)
            }
            .fileImporter(
                isPresented: showBlueprintImporter,
                allowedContentTypes: HeatmapImportContentTypes.blueprint,
                allowsMultipleSelection: false
            ) { result in
                onBlueprintImport(result)
            }
    }
}
