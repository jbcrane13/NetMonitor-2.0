import NetMonitorCore
import RoomPlan
import SwiftUI

// MARK: - RoomPlanScannerView

struct RoomPlanScannerView: View {
    /// Optional callback when a blueprint is completed and ready for heatmap use.
    var onBlueprintComplete: ((BlueprintProject) -> Void)?

    @State private var viewModel = RoomPlanScannerViewModel()
    @State private var showDocumentExporter = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch viewModel.scanState {
            case .idle:
                scanSetupView
            case .scanning:
                activeScanView
            case .processing:
                processingView
            case .complete:
                scanCompleteView
            case .error(let message):
                errorView(message: message)
            }
        }
        .themedBackground()
        .navigationTitle("Room Scanner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") {
                    dismiss()
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("roomScanner_button_close")
            }
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let url = viewModel.exportedFileURL {
                ShareSheet(activityItems: [url])
                    .accessibilityIdentifier("roomScanner_label_shareSheet")
            }
        }
        .sheet(isPresented: $showDocumentExporter) {
            if let url = viewModel.exportedFileURL {
                DocumentExporterView(sourceURL: url)
                    .accessibilityIdentifier("roomScanner_label_documentExporter")
            }
        }
    }

    // MARK: - Setup View

    private var scanSetupView: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                VStack(spacing: 16) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.Colors.accent)
                        .accessibilityIdentifier("roomScanner_image_setup")

                    Text("3D Room Scanner")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Scan every room in your home to build a multi-room floor plan that Mac can import as a base map for Wi-Fi heatmap surveys.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)

                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.isLiDARAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(viewModel.isLiDARAvailable ? Theme.Colors.success : Theme.Colors.warning)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.isLiDARAvailable ? "LiDAR Available" : "No LiDAR Sensor")
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text(viewModel.isLiDARAvailable
                                ? "Full precision room scanning enabled."
                                : "Room scanning will use ARKit (reduced accuracy).")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer()
                    }
                }
                .accessibilityIdentifier("roomScanner_card_lidar")

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Scan Details")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.Colors.textPrimary)

                        TextField("Project Name", text: $viewModel.projectName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("roomScanner_textfield_projectName")

                        TextField("Building Name (optional)", text: $viewModel.buildingName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("roomScanner_textfield_buildingName")

                        HStack {
                            TextField("Floor Label", text: $viewModel.floorLabel)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("roomScanner_textfield_floorLabel")

                            Stepper("Floor #\(viewModel.floorNumber)", value: $viewModel.floorNumber, in: -5...200)
                                .accessibilityIdentifier("roomScanner_stepper_floorNumber")
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to Scan")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.Colors.textPrimary)

                        instructionRow(number: 1, text: "Walk the perimeter of the first room until walls are detected")
                        instructionRow(number: 2, text: "Tap Next Room to pause, then walk through the doorway")
                        instructionRow(number: 3, text: "Scan each adjacent room the same way — keep the camera pointing at walls while moving")
                        instructionRow(number: 4, text: "Tap Finish when every room is captured — the app builds the floor plan")
                    }
                }

                Button {
                    viewModel.startScanning()
                } label: {
                    HStack {
                        Image(systemName: "camera.viewfinder")
                        Text("Start Scanning")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("roomScanner_button_startScan")
                .padding(.top, 8)
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.Colors.accent.opacity(0.8), in: Circle())

            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Active Scan View

    private var activeScanView: some View {
        RoomPlanScanContainer(viewModel: viewModel)
            .ignoresSafeArea()
            .accessibilityIdentifier("roomScanner_label_scanContainer")
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.Colors.accent)

            Text(processingTitle)
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(processingSubtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("roomScanner_label_processing")
    }

    private var processingTitle: String {
        switch viewModel.processingPhase {
        case .mergingRooms: "Merging rooms…"
        case .generatingBlueprint: "Generating floor plan…"
        case .renderingPreview: "Rendering preview…"
        case .saving: "Saving blueprint…"
        }
    }

    private var processingSubtitle: String {
        let count = viewModel.roomsCapturedCount
        let suffix = count == 1 ? "room" : "rooms"
        return "\(count) \(suffix) captured"
    }

    // MARK: - Complete View

    private var scanCompleteView: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                if let image = viewModel.previewImage {
                    GlassCard {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Text("Floor Plan Preview")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                Label("2D from 3D scan", systemImage: "cube.transparent")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.Colors.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.Colors.accent.opacity(0.15))
                                    .clipShape(Capsule())
                            }

                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityIdentifier("roomScanner_image_preview")
                        }
                    }
                }

                if let blueprint = viewModel.completedBlueprint {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scan Results")
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.Colors.textPrimary)

                            let totalWalls = blueprint.floors.reduce(0) { $0 + $1.wallSegments.count }
                            let totalRooms = blueprint.floors.reduce(0) { $0 + $1.roomLabels.count }

                            detailRow(label: "Floors", value: "\(blueprint.floors.count)")
                            detailRow(label: "Rooms Detected", value: "\(max(totalRooms, viewModel.roomsCapturedCount))")
                            detailRow(label: "Walls", value: "\(totalWalls)")
                            if let firstFloor = blueprint.floors.first {
                                let floorSize = String(
                                    format: "%.1f x %.1f m",
                                    firstFloor.widthMeters,
                                    firstFloor.heightMeters
                                )
                                detailRow(label: "Primary Floor", value: floorSize)
                            }
                            detailRow(label: "LiDAR Used", value: blueprint.metadata.hasLiDAR ? "Yes" : "No")

                            if viewModel.localSaveURL != nil {
                                Divider().background(Theme.Colors.divider)
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.Colors.success)
                                        .font(.caption)
                                    Text("Saved to Documents/Blueprints")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("roomScanner_card_results")
                }

                VStack(spacing: 12) {
                    Button {
                        viewModel.exportBlueprint()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Blueprint")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityIdentifier("roomScanner_button_share")

                    Button {
                        saveToFiles()
                    } label: {
                        HStack {
                            Image(systemName: "icloud.and.arrow.up")
                            Text("Save to iCloud Drive / Files")
                        }
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.Colors.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityIdentifier("roomScanner_button_saveFiles")

                    if onBlueprintComplete != nil {
                        Button {
                            if let blueprint = viewModel.completedBlueprint {
                                onBlueprintComplete?(blueprint)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "wifi.circle")
                                Text("Use for Wi-Fi Heatmap")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.Colors.success, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityIdentifier("roomScanner_button_useForHeatmap")
                    }

                    Button {
                        viewModel.resetScan()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Scan Again")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .accessibilityIdentifier("roomScanner_button_rescan")
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func saveToFiles() {
        guard var blueprint = viewModel.completedBlueprint else { return }
        blueprint.name = viewModel.projectName.isEmpty ? "Room Scan" : viewModel.projectName

        let fileName = blueprint.name
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).netmonblueprint")

        do {
            let manager = BlueprintSaveLoadManager()
            try manager.save(project: blueprint, to: tempURL)
            viewModel.exportedFileURL = tempURL
            showDocumentExporter = true
        } catch {
            viewModel.scanState = .error("Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        RoomScanErrorView(message: message, onRetry: { viewModel.resetScan() })
    }
}

// MARK: - RoomScanErrorView

private struct RoomScanErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.error)

            Text("Scan Error")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onRetry) {
                Text("Try Again")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityIdentifier("roomScanner_button_retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("roomScanner_label_error")
    }
}

// MARK: - RoomPlan Scan Container (UIViewControllerRepresentable)

struct RoomPlanScanContainer: UIViewControllerRepresentable {
    let viewModel: RoomPlanScannerViewModel

    func makeUIViewController(context: Context) -> RoomPlanScanViewController {
        let controller = RoomPlanScanViewController()
        controller.viewModel = viewModel
        return controller
    }

    func updateUIViewController(_ uiViewController: RoomPlanScanViewController, context: Context) {}
}


// MARK: - DocumentExporterView

/// Wraps UIDocumentPickerViewController to let users save to iCloud Drive / Files.
struct DocumentExporterView: UIViewControllerRepresentable {
    let sourceURL: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [sourceURL], asCopy: true)
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    RoomPlanScannerView()
}
