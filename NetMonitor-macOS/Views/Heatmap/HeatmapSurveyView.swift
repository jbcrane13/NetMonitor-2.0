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
        HeatmapCanvasView(
            floorPlanImageData: viewModel.surveyProject?.floorPlan.imageData,
            measurementPoints: viewModel.measurementPoints,
            calibrationPoints: viewModel.calibrationPoints,
            isCalibrating: viewModel.isCalibrating,
            heatmapImage: heatmapImage,
            scale: scale,
            offset: offset,
            onTap: { normalizedPoint in
                if viewModel.isCalibrating {
                    viewModel.addCalibrationPoint(at: normalizedPoint)
                } else {
                    Task {
                        await viewModel.takeMeasurement(at: normalizedPoint)
                        updateHeatmap()
                    }
                }
            },
            onPointDelete: { pointId in
                viewModel.deletePoint(id: pointId)
                updateHeatmap()
            }
        )
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

            Button {
                exportPDF()
            } label: {
                Label("Export PDF", systemImage: "doc.richtext")
            }
            .disabled(viewModel.surveyProject == nil || viewModel.measurementPoints.isEmpty)

            Button {
                viewModel.undo()
                updateHeatmap()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo())
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

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(viewModel.surveyProject?.name ?? "Survey")-Report"

        if panel.runModal() == .OK, let url = panel.url {
            if let pdfData = viewModel.generatePDFReport() {
                do {
                    try pdfData.write(to: url)
                } catch {
                    print("PDF export failed: \(error)")
                }
            }
        }
    }
}

// MARK: - HeatmapCanvasView

struct HeatmapCanvasView: NSViewRepresentable {
    let floorPlanImageData: Data?
    let measurementPoints: [MeasurementPoint]
    let calibrationPoints: [CalibrationPoint]
    let isCalibrating: Bool
    let heatmapImage: NSImage?
    let scale: CGFloat
    let offset: CGSize
    let onTap: (CGPoint) -> Void
    let onPointDelete: (UUID) -> Void

    func makeNSView(context: Context) -> HeatmapCanvasNSView {
        let view = HeatmapCanvasNSView()
        view.onTap = onTap
        view.onPointDelete = onPointDelete
        return view
    }

    func updateNSView(_ nsView: HeatmapCanvasNSView, context: Context) {
        nsView.floorPlanImageData = floorPlanImageData
        nsView.measurementPoints = measurementPoints
        nsView.calibrationPoints = calibrationPoints
        nsView.isCalibrating = isCalibrating
        nsView.heatmapImage = heatmapImage
        nsView.scale = scale
        nsView.offset = offset
        nsView.needsDisplay = true
    }
}

class HeatmapCanvasNSView: NSView {
    var floorPlanImageData: Data?
    var measurementPoints: [MeasurementPoint] = []
    var calibrationPoints: [CalibrationPoint] = []
    var isCalibrating: Bool = false
    var heatmapImage: NSImage?
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero
    var onTap: ((CGPoint) -> Void)?
    var onPointDelete: ((UUID) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Background
        NSColor.black.withAlphaComponent(0.05).setFill()
        dirtyRect.fill()

        guard let imageData = floorPlanImageData,
              let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let imageSize = nsImage.size
        let aspectRatio = imageSize.width / imageSize.height
        let containerAspect = bounds.width / bounds.height

        var displayedWidth: CGFloat
        var displayedHeight: CGFloat
        if aspectRatio > containerAspect {
            displayedWidth = bounds.width
            displayedHeight = bounds.width / aspectRatio
        } else {
            displayedWidth = bounds.height * aspectRatio
            displayedHeight = bounds.height
        }

        let offsetX = (bounds.width - displayedWidth) / 2
        let offsetY = (bounds.height - displayedHeight) / 2

        // Draw floor plan
        let imageRect = CGRect(x: offsetX, y: offsetY, width: displayedWidth, height: displayedHeight)
        context.draw(cgImage, in: imageRect)

        // Draw heatmap overlay
        if let heatmap = heatmapImage,
           let heatmapCG = heatmap.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.saveGState()
            context.setAlpha(0.7)
            context.draw(heatmapCG, in: imageRect)
            context.restoreGState()
        }

        // Draw measurement points
        for point in measurementPoints {
            let x = offsetX + point.floorPlanX * displayedWidth
            let y = offsetY + (1 - point.floorPlanY) * displayedHeight
            let rect = CGRect(x: x - 6, y: y - 6, width: 12, height: 12)

            colorForRSSI(point.rssi).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }

        // Draw calibration points
        if isCalibrating {
            for (index, point) in calibrationPoints.enumerated() {
                let x = offsetX + point.pixelX * displayedWidth
                let y = offsetY + (1 - point.pixelY) * displayedHeight
                let rect = CGRect(x: x - 10, y: y - 10, width: 20, height: 20)

                NSColor.blue.setStroke()
                NSBezierPath(ovalIn: rect).stroke()

                NSColor.blue.withAlphaComponent(0.3).setFill()
                NSBezierPath(ovalIn: rect).fill()

                let label = "\(index + 1)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 10),
                    .foregroundColor: NSColor.white
                ]
                let size = label.size(withAttributes: attrs)
                label.draw(at: CGPoint(x: x - size.width/2, y: y - size.height/2), withAttributes: attrs)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        handleTap(at: location)
    }

    private func handleTap(at location: CGPoint) {
        guard let imageData = floorPlanImageData,
              let nsImage = NSImage(data: imageData) else { return }

        let imageSize = nsImage.size
        let aspectRatio = imageSize.width / imageSize.height
        let containerAspect = bounds.width / bounds.height

        var displayedWidth: CGFloat
        var displayedHeight: CGFloat
        if aspectRatio > containerAspect {
            displayedWidth = bounds.width
            displayedHeight = bounds.width / aspectRatio
        } else {
            displayedWidth = bounds.height * aspectRatio
            displayedHeight = bounds.height
        }

        let offsetX = (bounds.width - displayedWidth) / 2
        let offsetY = (bounds.height - displayedHeight) / 2

        let tapX = (location.x - offsetX) / displayedWidth
        let tapY = 1.0 - (location.y - offsetY) / displayedHeight

        guard tapX >= 0 && tapX <= 1 && tapY >= 0 && tapY <= 1 else { return }

        onTap?(CGPoint(x: tapX, y: tapY))
    }

    private func colorForRSSI(_ rssi: Int) -> NSColor {
        switch rssi {
        case -50...0: return .systemGreen
        case -60 ..< -50: return .systemYellow
        case -70 ..< -60: return .systemOrange
        default: return .systemRed
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
