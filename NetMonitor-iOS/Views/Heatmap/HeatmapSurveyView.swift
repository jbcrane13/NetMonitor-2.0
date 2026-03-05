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

                // Tap to measure
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let normalizedX = min(max(location.x / geometry.size.width, 0), 1)
                        let normalizedY = min(max(location.y / geometry.size.height, 0), 1)
                        Task {
                            await viewModel.takeMeasurement(at: CGPoint(x: normalizedX, y: normalizedY))
                            updateHeatmap()
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

            if let lastPoint = viewModel.measurementPoints.last {
                HStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .foregroundStyle(colorForRSSI(lastPoint.rssi))
                    Text("\(lastPoint.rssi) dBm")
                        .font(.headline)
                        .monospacedDigit()
                }
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
