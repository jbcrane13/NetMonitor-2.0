import NetMonitorCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - WiFiHeatmapView

struct WiFiHeatmapView: View {
    @State private var viewModel = WiFiHeatmapViewModel()

    var body: some View {
        HSplitView {
            if !viewModel.isSidebarCollapsed {
                HeatmapSidebarView(viewModel: viewModel)
            }
            canvas
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $viewModel.showImportSheet,
            allowedContentTypes: [.png, .jpeg, .pdf, .heic],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $viewModel.showCalibrationSheet) {
            CalibrationSheet(viewModel: viewModel)
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityIdentifier("heatmap_view")
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
                    viewModel.showImportSheet = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("heatmap_button_import")

                Button("Open Project") {
                    loadProject()
                }
                .accessibilityIdentifier("heatmap_button_open")
            }
        }
        .padding(40)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Project name
            if let name = viewModel.surveyProject?.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Visualization picker (toolbar)
            if viewModel.surveyProject != nil {
                Picker("Viz", selection: $viewModel.selectedVisualization) {
                    ForEach(HeatmapVisualization.allCases, id: \.self) { viz in
                        Text(viz.displayName).tag(viz)
                    }
                }
                .frame(width: 140)
                .onChange(of: viewModel.selectedVisualization) { _, _ in
                    if viewModel.isHeatmapGenerated { viewModel.generateHeatmap() }
                }
                .accessibilityIdentifier("heatmap_toolbar_viz")
            }

            // Point count
            if !viewModel.measurementPoints.isEmpty {
                Text("\(viewModel.filteredPoints.count) pts")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Import
            Button {
                viewModel.showImportSheet = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("heatmap_toolbar_import")

            // Calibrate
            if viewModel.isCalibrating {
                Button {
                    viewModel.cancelCalibration()
                } label: {
                    Label("Cancel Calibration", systemImage: "xmark")
                }
            } else {
                Button {
                    viewModel.startCalibration()
                } label: {
                    Label("Calibrate", systemImage: "ruler")
                }
                .disabled(viewModel.surveyProject == nil)
                .accessibilityIdentifier("heatmap_toolbar_calibrate")
            }

            // Save
            Button { saveProject() } label: {
                Label("Save", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.surveyProject == nil)
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityIdentifier("heatmap_toolbar_save")

            // Open
            Button { loadProject() } label: {
                Label("Open", systemImage: "folder")
            }
            .accessibilityIdentifier("heatmap_toolbar_open")

            // Export
            Menu {
                Button("Export PNG") { exportImage(format: .png) }
                Button("Export PDF") { exportPDF() }
            } label: {
                Label("Export", systemImage: "doc.richtext")
            }
            .disabled(viewModel.surveyProject == nil || viewModel.measurementPoints.isEmpty)
            .accessibilityIdentifier("heatmap_toolbar_export")

            // Undo
            Button {
                viewModel.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityIdentifier("heatmap_toolbar_undo")

            // Sidebar toggle
            Button {
                viewModel.isSidebarCollapsed.toggle()
            } label: {
                Label("Sidebar", systemImage: viewModel.isSidebarCollapsed ? "sidebar.left" : "sidebar.left")
            }
            .accessibilityIdentifier("heatmap_toolbar_sidebar")
        }
    }

    // MARK: - File Handling

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try viewModel.importFloorPlan(from: url)
            } catch {
                print("Import failed: \(error)")
            }
        case .failure(let error):
            print("Import error: \(error)")
        }
    }

    private func saveProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "netmonsurvey")].compactMap { $0 }
        panel.nameFieldStringValue = viewModel.surveyProject?.name ?? "Survey"
        if panel.runModal() == .OK, let url = panel.url {
            try? viewModel.saveProject(to: url)
        }
    }

    private func loadProject() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? viewModel.loadProject(from: url)
        }
    }

    private func exportImage(format: NSBitmapImageRep.FileType) {
        guard let data = viewModel.exportPNG(canvasSize: CGSize(width: 800, height: 600)) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(viewModel.surveyProject?.name ?? "heatmap")-export"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func exportPDF() {
        // Reuse the ViewModel's PDF generation (port from old ViewModel if needed)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(viewModel.surveyProject?.name ?? "heatmap")-report"
        if panel.runModal() == .OK, let url = panel.url {
            if let pngData = viewModel.exportPNG(canvasSize: CGSize(width: 1600, height: 1200)) {
                try? pngData.write(to: url)
            }
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
                    let w = Double(project.floorPlan.pixelWidth) * metersPerPixel
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
