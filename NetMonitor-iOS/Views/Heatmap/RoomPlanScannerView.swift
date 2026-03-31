import NetMonitorCore
import RoomPlan
import SwiftUI

// MARK: - RoomPlanScannerView

struct RoomPlanScannerView: View {
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
                // Header illustration
                VStack(spacing: 16) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.Colors.accent)
                        .accessibilityIdentifier("roomScanner_image_setup")

                    Text("3D Room Scanner")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Scan your room to create a floor plan blueprint that can be used as a base map for Wi-Fi heatmap surveys on Mac.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)

                // LiDAR status
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

                // Project details
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

                // Instructions
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to Scan")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.Colors.textPrimary)

                        instructionRow(number: 1, text: "Point your camera at the room's walls and floor")
                        instructionRow(number: 2, text: "Walk slowly around the perimeter of the room")
                        instructionRow(number: 3, text: "Tap Done when all walls are detected")
                        instructionRow(number: 4, text: "Export the blueprint to your Mac via AirDrop or Files")
                    }
                }

                // Start button
                Button {
                    viewModel.scanState = .scanning
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

            Text("Processing Room Scan...")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Generating floor plan from 3D scan data")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("roomScanner_label_processing")
    }

    // MARK: - Complete View

    private var scanCompleteView: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                // Preview image
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

                // Scan details
                if let blueprint = viewModel.completedBlueprint,
                   let floor = blueprint.floors.first {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scan Results")
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.Colors.textPrimary)

                            detailRow(label: "Dimensions", value: String(format: "%.1f x %.1f m", floor.widthMeters, floor.heightMeters))
                            detailRow(label: "Walls Detected", value: "\(floor.wallSegments.count)")
                            detailRow(label: "Rooms Labeled", value: "\(floor.roomLabels.count)")
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

                // Action buttons
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

        // Save to temp first, then present document picker to move to iCloud Drive / Files
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

            Button {
                viewModel.resetScan()
            } label: {
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

// MARK: - RoomPlanScanViewController

final class RoomPlanScanViewController: UIViewController, RoomCaptureSessionDelegate, @preconcurrency RoomCaptureViewDelegate {

    var viewModel: RoomPlanScannerViewModel?
    private var roomCaptureView: RoomCaptureView!
    private var captureSession: RoomCaptureSession!
    private var doneButton: UIButton!
    private var cancelButton: UIButton!

    // Strong reference kept across async boundary so the Task in captureSession(_:didEndWith:)
    // can complete even after SwiftUI removes this UIViewController from the hierarchy.
    nonisolated(unsafe) private var processingViewModel: RoomPlanScannerViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        captureSession = roomCaptureView.captureSession
        view.addSubview(roomCaptureView)

        setupOverlayButtons()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stop the session and clear the delegate to release all retained ARFrames
        // when SwiftUI transitions away from this view controller.
        captureSession.stop()
        roomCaptureView.captureSession.delegate = nil
    }

    private func setupOverlayButtons() {
        // Done button
        doneButton = UIButton(type: .system)
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = UIColor.systemBlue
        doneButton.layer.cornerRadius = 12
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.accessibilityIdentifier = "roomScanner_button_done"
        view.addSubview(doneButton)

        // Cancel button
        cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 15)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = UIColor.darkGray.withAlphaComponent(0.7)
        cancelButton.layer.cornerRadius = 12
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.accessibilityIdentifier = "roomScanner_button_cancelScan"
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            doneButton.widthAnchor.constraint(equalToConstant: 100),
            doneButton.heightAnchor.constraint(equalToConstant: 44),

            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.widthAnchor.constraint(equalToConstant: 100),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func startSession() {
        let config = RoomCaptureSession.Configuration()
        captureSession.run(configuration: config)
    }

    @objc private func doneTapped() {
        guard let viewModel else { return }
        doneButton.isEnabled = false
        cancelButton.isEnabled = false

        // Capture strong ref BEFORE stop() — SwiftUI may remove this UIViewController
        // from the hierarchy (by transitioning from .scanning to .processing) before the
        // RoomBuilder async processing completes.
        processingViewModel = viewModel

        // Stop the session first, then transition state. This ensures captureSession(_:didEndWith:)
        // fires while processingViewModel is already set. The viewWillDisappear stop (triggered by
        // the state transition) is idempotent and harmless.
        captureSession.stop()

        // Transition after stop so the delegate nil-out in viewWillDisappear doesn't race with
        // the session ending — by this point didEndWith has been dispatched.
        viewModel.scanState = .processing
    }

    @objc private func cancelTapped() {
        captureSession.stop()
        Task { @MainActor in
            viewModel?.resetScan()
        }
    }

    // MARK: - RoomCaptureSessionDelegate

    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        let vm = processingViewModel
        if let error {
            Task { @MainActor in
                vm?.handleScanError(error)
            }
            return
        }

        // Use RoomBuilder directly instead of the built-in RoomCaptureView review UI.
        // This bypasses the post-capture editing screen whose "Done" button can pop the
        // SwiftUI NavigationStack before our state machine reaches .complete.
        let roomBuilder = RoomBuilder(options: .beautifyObjects)
        Task {
            do {
                let capturedRoom = try await roomBuilder.capturedRoom(from: data)
                await MainActor.run {
                    vm?.processCapturedRoom(capturedRoom)
                }
            } catch {
                await MainActor.run {
                    vm?.handleScanError(error)
                }
            }
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        // Real-time updates during scan — RoomCaptureView handles visualization
    }

    // MARK: - RoomCaptureViewDelegate

    nonisolated func captureView(_ view: RoomCaptureView, didPresent processedResult: CapturedRoom, error: (any Error)?) {
        // No-op: processing is now handled entirely in captureSession(_:didEndWith:) via
        // RoomBuilder, which bypasses this built-in review step.
    }
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
