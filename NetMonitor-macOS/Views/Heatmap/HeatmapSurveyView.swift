import SwiftUI
import NetMonitorCore
import UniformTypeIdentifiers

struct HeatmapSurveyView: View {
    @State private var viewModel = HeatmapSurveyViewModel()
    @State private var heatmapImage: NSImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        HSplitView {
            sidebar
            detailArea
        }
        .frame(minWidth: 900, minHeight: 600)
        .fileImporter(
            isPresented: $viewModel.showImportSheet,
            allowedContentTypes: [.png, .jpeg, .pdf, .heic],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            Section("Measurement Mode") {
                Picker("Mode", selection: $viewModel.measurementMode) {
                    Text("Passive (RSSI only)").tag(HeatmapSurveyViewModel.MeasurementMode.passive)
                    Text("Active (+ Speed/Latency)").tag(HeatmapSurveyViewModel.MeasurementMode.active)
                }
                .pickerStyle(.segmented)

                if viewModel.measurementMode == .active {
                    Text("Active mode runs speed tests at each point - takes longer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Visualization") {
                Picker("Type", selection: $viewModel.selectedVisualization) {
                    ForEach(HeatmapVisualization.allCases, id: \.self) { viz in
                        Text(viz.displayName).tag(viz)
                    }
                }
                .onChange(of: viewModel.selectedVisualization) { _, _ in
                    updateHeatmap()
                }
            }

            Section("Statistics") {
                LabeledContent("Points", value: "\(viewModel.measurementPoints.count)")
                if let avg = viewModel.surveyProject?.averageRSSI {
                    LabeledContent("Avg RSSI", value: String(format: "%.1f dBm", avg))
                }
                if let min = viewModel.surveyProject?.minRSSI {
                    LabeledContent("Min RSSI", value: "\(min) dBm")
                }
                if let max = viewModel.surveyProject?.maxRSSI {
                    LabeledContent("Max RSSI", value: "\(max) dBm")
                }
            }

            Section("Actions") {
                Button("Clear Measurements") {
                    viewModel.clearMeasurements()
                    heatmapImage = nil
                }
                .disabled(viewModel.measurementPoints.isEmpty)
            }
        }
        .frame(minWidth: 220)
    }

    // MARK: - Detail Area

    private var detailArea: some View {
        Group {
            if viewModel.surveyProject != nil {
                measurementCanvas
            } else {
                emptyState
            }
        }
    }

    // MARK: - Canvas

    private var measurementCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                // Floor plan image
                if let imageData = viewModel.surveyProject?.floorPlan.imageData,
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale = $0 }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { offset = $0.translation }
                        )
                }

                // Heatmap overlay
                if let heatmap = heatmapImage {
                    Image(nsImage: heatmap)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .opacity(0.7)
                }

                // Measurement points overlay
                ForEach(viewModel.measurementPoints) { point in
                    Circle()
                        .fill(colorForRSSI(point.rssi))
                        .frame(width: 12, height: 12)
                        .position(
                            x: point.floorPlanX * geometry.size.width * scale + offset.width,
                            y: point.floorPlanY * geometry.size.height * scale + offset.height
                        )
                }

                // Click to measure
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let normalizedX = location.x / (geometry.size.width * scale)
                        let normalizedY = location.y / (geometry.size.height * scale)
                        Task {
                            await viewModel.takeMeasurement(at: CGPoint(x: normalizedX, y: normalizedY))
                            updateHeatmap()
                        }
                    }

                // Measuring indicator
                if viewModel.isMeasuring {
                    ProgressView()
                        .scaleEffect(2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color.black.opacity(0.05))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Floor Plan")
                .font(.title2)

            Text("Import a floor plan image to start measuring WiFi signal strength")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Import Floor Plan") {
                viewModel.showImportSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.showImportSheet = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }

            Button {
                saveProject()
            } label: {
                Label("Save", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.surveyProject == nil)

            Button {
                loadProject()
            } label: {
                Label("Open", systemImage: "folder")
            }
        }
    }

    // MARK: - Helpers

    private func handleImport(_ result: Result<[URL], Error>) {
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

    private func updateHeatmap() {
        if let cgImage = viewModel.renderHeatmap() {
            heatmapImage = NSImage(cgImage: cgImage, size: NSSize(
                width: cgImage.width,
                height: cgImage.height
            ))
        }
    }

    private func colorForRSSI(_ rssi: Int) -> Color {
        switch rssi {
        case -50...0: return .green
        case -60 ..< -50: return .yellow
        case -70 ..< -60: return .orange
        default: return .red
        }
    }

    private func saveProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "netmonsurvey")!]
        panel.nameFieldStringValue = viewModel.surveyProject?.name ?? "Survey"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try viewModel.saveProject(to: url)
            } catch {
                print("Save failed: \(error)")
            }
        }
    }

    private func loadProject() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try viewModel.loadProject(from: url)
                updateHeatmap()
            } catch {
                print("Load failed: \(error)")
            }
        }
    }
}
