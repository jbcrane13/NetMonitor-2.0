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
        .sheet(isPresented: $viewModel.showCalibrationSheet) {
            CalibrationSheetMac(viewModel: viewModel)
        }
        .toolbar {
            toolbarContent
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
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

                // Calibration points overlay
                if viewModel.isCalibrating {
                    ForEach(viewModel.calibrationPoints) { point in
                        ZStack {
                            Circle()
                                .stroke(Color.blue, lineWidth: 3)
                                .frame(width: 20, height: 20)
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 20, height: 20)
                            Text(viewModel.calibrationPoints.firstIndex(where: { $0.id == point.id }) == 0 ? "1" : "2")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .position(
                            x: point.pixelX * geometry.size.width * scale + offset.width,
                            y: point.pixelY * geometry.size.height * scale + offset.height
                        )
                    }
                }

                // Calibration points overlay
                if viewModel.isCalibrating {
                    ForEach(viewModel.calibrationPoints) { point in
                        ZStack {
                            Circle()
                                .stroke(Color.blue, lineWidth: 3)
                                .frame(width: 20, height: 20)
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 20, height: 20)
                            Text(viewModel.calibrationPoints.firstIndex(where: { $0.id == point.id }) == 0 ? "1" : "2")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                        .position(
                            x: point.pixelX * geometry.size.width * scale + offset.width,
                            y: point.pixelY * geometry.size.height * scale + offset.height
                        )
                    }
                }

                // Click to measure or calibrate
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let normalizedX = location.x / (geometry.size.width * scale)
                        let normalizedY = location.y / (geometry.size.height * scale)
                        let point = CGPoint(x: normalizedX, y: normalizedY)

                        if viewModel.isCalibrating {
                            viewModel.addCalibrationPoint(at: point)
                        } else {
                            Task {
                                await viewModel.takeMeasurement(at: point)
                                updateHeatmap()
                            }
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
            // Live RSSI badge (AC-1.4)
            if viewModel.surveyProject != nil {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                        .foregroundStyle(colorForRSSI(viewModel.currentRSSI))
                    Text("\(viewModel.currentRSSI) dBm")
                        .foregroundStyle(colorForRSSI(viewModel.currentRSSI))
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
            }

            Divider()

            Button {
                viewModel.showImportSheet = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }

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

// MARK: - Calibration Sheet (macOS)

struct CalibrationSheetMac: View {
    @Bindable var viewModel: HeatmapSurveyViewModel
    @State private var distanceText: String = "5.0"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Calibrate Floor Plan Scale")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Known Distance")
                    .font(.subheadline)

                HStack {
                    TextField("Distance", text: $distanceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("meters")
                        .foregroundStyle(.secondary)
                }

                Text("Enter the real-world distance between the two calibration points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.calibrationPoints.count == 2 {
                Divider()

                let p1 = viewModel.calibrationPoints[0]
                let p2 = viewModel.calibrationPoints[1]
                let pixelDistance = sqrt(
                    pow(p1.pixelX - p2.pixelX, 2) +
                    pow(p1.pixelY - p2.pixelY, 2)
                )
                let metersPerPixel = CalibrationPoint.metersPerPixel(
                    pointA: p1,
                    pointB: p2,
                    knownDistanceMeters: Double(distanceText) ?? 5.0
                )

                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Pixel Distance:") {
                        Text(String(format: "%.1f px", pixelDistance))
                    }
                    LabeledContent("Scale:") {
                        Text(String(format: "%.4f m/px", metersPerPixel))
                    }
                    if let project = viewModel.surveyProject {
                        let widthMeters = Double(project.floorPlan.pixelWidth) * metersPerPixel
                        let heightMeters = Double(project.floorPlan.pixelHeight) * metersPerPixel
                        LabeledContent("Floor Plan Size:") {
                            Text(String(format: "%.1f x %.1f m", widthMeters, heightMeters))
                        }
                    }
                }
                .font(.caption)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    viewModel.cancelCalibration()
                    dismiss()
                }

                Spacer()

                Button("Save Calibration") {
                    if let distance = Double(distanceText) {
                        viewModel.completeCalibration(withDistance: distance)
                        dismiss()
                    }
                }
                .disabled(Double(distanceText) == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320, height: 300)
    }
}
