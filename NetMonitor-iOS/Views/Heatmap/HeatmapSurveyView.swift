import SwiftUI
import NetMonitorCore
import PhotosUI

struct HeatmapSurveyView: View {
    @State private var viewModel = HeatmapSurveyViewModel()
    @State private var heatmapImage: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            if viewModel.surveyProject != nil {
                measurementCanvas
            } else {
                emptyState
            }

            // Floating RSSI card
            if viewModel.isMeasuring || !viewModel.measurementPoints.isEmpty {
                floatingRSSICard
            }
        }
        .navigationTitle("WiFi Survey")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        selectedPhotoItem = nil
                        viewModel.showImportSheet = true
                    } label: {
                        Label("Import from Photos", systemImage: "photo")
                    }

                    Button {
                        // File picker handled elsewhere
                    } label: {
                        Label("Import from Files", systemImage: "folder")
                    }

                    Divider()

                    Picker("Mode", selection: $viewModel.measurementMode) {
                        Text("Passive").tag(HeatmapSurveyViewModel.MeasurementMode.passive)
                        Text("Active").tag(HeatmapSurveyViewModel.MeasurementMode.active)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Visualization", selection: $viewModel.selectedVisualization) {
                        ForEach(HeatmapVisualization.allCases, id: \.self) { viz in
                            Text(viz.displayName).tag(viz)
                        }
                    }

                    Divider()

                    Button("Clear Points") {
                        viewModel.clearMeasurements()
                        heatmapImage = nil
                    }

                    Divider()

                    if viewModel.isCalibrating {
                        Button("Cancel Calibration") {
                            viewModel.cancelCalibration()
                        }
                    } else {
                        Button("Calibrate Scale") {
                            viewModel.startCalibration()
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .photosPicker(isPresented: $viewModel.showImportSheet, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newValue in
            handlePhotoImport(newValue)
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .sheet(isPresented: $viewModel.showCalibrationSheet) {
            CalibrationSheet(viewModel: viewModel)
        }
    }

    // MARK: - Canvas

    private var measurementCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                // Floor plan
                if let imageData = viewModel.surveyProject?.floorPlan.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
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
                    Image(uiImage: heatmap)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .opacity(0.7)
                }

                // Measurement points
                ForEach(viewModel.measurementPoints) { point in
                    Circle()
                        .fill(colorForRSSI(point.rssi))
                        .frame(width: 16, height: 16)
                        .position(
                            x: point.floorPlanX * geometry.size.width * scale + offset.width,
                            y: point.floorPlanY * geometry.size.height * scale + offset.height
                        )
                }

                // Calibration points
                if viewModel.isCalibrating {
                    ForEach(viewModel.calibrationPoints) { point in
                        ZStack {
                            Circle()
                                .stroke(Color.blue, lineWidth: 3)
                                .frame(width: 24, height: 24)
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 24, height: 24)
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

                // Tap to measure or calibrate
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let normalizedX = min(max(location.x / geometry.size.width, 0), 1)
                        let normalizedY = min(max(location.y / geometry.size.height, 0), 1)
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

                // Loading indicator
                if viewModel.isMeasuring {
                    ProgressView()
                        .scaleEffect(2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Floor Plan")
                .font(.title2)

            Text("Import a floor plan to start measuring WiFi signal")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Location permission prompt
            if !viewModel.isLocationAuthorized {
                VStack(spacing: 8) {
                    Text("Location access required to read WiFi signal strength")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)

                    Button("Grant Location Permission") {
                        viewModel.requestLocationPermission()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Text("Import from Photos")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }

    // MARK: - Floating RSSI Card

    private var floatingRSSICard: some View {
        VStack(spacing: 4) {
            Text("\(viewModel.measurementPoints.count) points")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Live RSSI indicator (AC-1.4)
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .foregroundStyle(colorForRSSI(viewModel.currentRSSI))
                Text("\(viewModel.currentRSSI) dBm")
                    .font(.headline)
                    .monospacedDigit()
            }

            if let ssid = viewModel.currentSSID {
                Text(ssid)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding()
    }

    // MARK: - Helpers

    private func handlePhotoImport(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                viewModel.importFloorPlan(
                    imageData: data,
                    width: Int(image.size.width),
                    height: Int(image.size.height)
                )
            }
        }
    }

    private func updateHeatmap() {
        if let cgImage = viewModel.renderHeatmap() {
            heatmapImage = UIImage(cgImage: cgImage)
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
}

// MARK: - Calibration Sheet

struct CalibrationSheet: View {
    @Bindable var viewModel: HeatmapSurveyViewModel
    @State private var distanceText: String = "5.0"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Distance") {
                    TextField("Distance", text: $distanceText)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                    Text("Enter the real-world distance between the two points in meters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Preview") {
                    if viewModel.calibrationPoints.count == 2 {
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

                        LabeledContent("Pixel Distance") {
                            Text(String(format: "%.1f px", pixelDistance))
                        }

                        LabeledContent("Scale") {
                            Text(String(format: "%.4f m/px", metersPerPixel))
                        }

                        if let project = viewModel.surveyProject {
                            let widthMeters = Double(project.floorPlan.pixelWidth) * metersPerPixel
                            let heightMeters = Double(project.floorPlan.pixelHeight) * metersPerPixel

                            LabeledContent("Floor Plan Size") {
                                Text(String(format: "%.1f × %.1f m", widthMeters, heightMeters))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Calibrate Scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelCalibration()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let distance = Double(distanceText) {
                            viewModel.completeCalibration(withDistance: distance)
                            dismiss()
                        }
                    }
                    .disabled(Double(distanceText) == nil)
                }
            }
        }
    }
}
