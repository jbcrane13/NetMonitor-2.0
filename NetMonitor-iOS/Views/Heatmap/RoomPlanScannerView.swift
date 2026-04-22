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
                                detailRow(label: "Primary Floor", value: String(format: "%.1f x %.1f m", firstFloor.widthMeters, firstFloor.heightMeters))
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

/// Manages the multi-room capture loop: scan a room → pause → scan next → ... → finish.
///
/// This controller owns its own internal phase (`.capturing` vs `.betweenRooms`) so it
/// can swap button sets without unmounting/remounting the `RoomCaptureView`. Keeping
/// the view controller alive between rooms is what lets RoomPlan preserve ARSession
/// world-tracking across doorways (`pauseARSession: false`), which is in turn what lets
/// `StructureBuilder` stitch rooms into a single coordinate space.
final class RoomPlanScanViewController: UIViewController, RoomCaptureSessionDelegate, RoomCaptureViewDelegate {

    // MARK: - Internal phase

    private enum Phase {
        /// Actively capturing a room (RoomCaptureSession is running).
        case capturing
        /// Session stopped between rooms; user chooses Next Room or Finish.
        case betweenRooms
        /// User chose Finish — session stopped and waiting for `didEndWith` to deliver
        /// the last CapturedRoomData, after which we hand off to the ViewModel to merge.
        case finishing
    }

    // MARK: - Properties

    var viewModel: RoomPlanScannerViewModel?

    private var roomCaptureView: RoomCaptureView!
    private var captureSession: RoomCaptureSession!

    // In-capture buttons
    private var nextRoomButton: UIButton!
    private var finishNowButton: UIButton!

    // Between-room buttons
    private var scanNextButton: UIButton!
    private var buildBlueprintButton: UIButton!

    // Always visible during scan flow
    private var cancelButton: UIButton!

    // Overlay panels
    private var statusContainer: UIView!
    private var statusLabel: UILabel!
    private var statusSubtitleLabel: UILabel!

    private var phase: Phase = .capturing

    /// Strong reference preserved across the async `didEndWith` boundary — SwiftUI may
    /// unmount this view controller while the session is still draining the last
    /// CapturedRoomData, and we need the VM reference to survive that.
    nonisolated(unsafe) private var processingViewModel: RoomPlanScannerViewModel?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        captureSession = roomCaptureView.captureSession
        view.addSubview(roomCaptureView)

        buildOverlay()
        applyPhase(.capturing)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        processingViewModel = viewModel
        startCapturingRoom()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Idempotent — if we're already stopped from a button tap, this is a no-op.
        captureSession.stop()
        roomCaptureView.captureSession.delegate = nil
    }

    // MARK: - Session control

    private func startCapturingRoom() {
        phase = .capturing
        let config = RoomCaptureSession.Configuration()
        captureSession.run(configuration: config)
        applyPhase(phase)
    }

    // MARK: - Button actions

    @objc private func nextRoomTapped() {
        guard phase == .capturing else { return }
        setButtonsEnabled(false)
        // Stop the session but keep ARSession alive so the next run() stitches into the
        // same world-tracking frame.
        captureSession.stop(pauseARSession: false)
    }

    @objc private func finishNowTapped() {
        guard phase == .capturing else { return }
        setButtonsEnabled(false)
        phase = .finishing
        captureSession.stop(pauseARSession: true)
    }

    @objc private func scanNextTapped() {
        guard phase == .betweenRooms else { return }
        startCapturingRoom()
    }

    @objc private func buildBlueprintTapped() {
        guard phase == .betweenRooms else { return }
        // No active session — just go straight to finalize. The VM already has all
        // captured rooms from the stream of didEndWith callbacks.
        phase = .finishing
        applyPhase(.finishing)
        viewModel?.finalizeScan()
    }

    @objc private func cancelTapped() {
        captureSession.stop(pauseARSession: true)
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

        Task { @MainActor [weak self] in
            guard let self else { return }
            vm?.didCompleteRoom(data)
            switch self.phase {
            case .finishing:
                vm?.finalizeScan()
            case .capturing, .betweenRooms:
                // `captureSession.stop(pauseARSession: false)` → delegate fires; we're
                // now between rooms waiting for the next action.
                self.phase = .betweenRooms
                self.applyPhase(.betweenRooms)
                self.setButtonsEnabled(true)
            }
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        // Real-time updates during scan — RoomCaptureView handles visualization.
    }

    // MARK: - RoomCaptureViewDelegate

    nonisolated func captureView(_ view: RoomCaptureView, didPresent processedResult: CapturedRoom, error: (any Error)?) {
        // No-op: custom post-processing runs in captureSession(_:didEndWith:).
    }

    // MARK: - Overlay

    private func buildOverlay() {
        // Status container (top center)
        statusContainer = UIView()
        statusContainer.translatesAutoresizingMaskIntoConstraints = false
        statusContainer.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusContainer.layer.cornerRadius = 14
        statusContainer.layer.masksToBounds = true
        view.addSubview(statusContainer)

        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.accessibilityIdentifier = "roomScanner_label_status"
        statusContainer.addSubview(statusLabel)

        statusSubtitleLabel = UILabel()
        statusSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        statusSubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        statusSubtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        statusSubtitleLabel.textAlignment = .center
        statusSubtitleLabel.numberOfLines = 0
        statusContainer.addSubview(statusSubtitleLabel)

        // Buttons
        nextRoomButton = makePrimaryButton(
            title: "Next Room",
            image: UIImage(systemName: "arrow.forward.circle.fill"),
            identifier: "roomScanner_button_nextRoom",
            action: #selector(nextRoomTapped)
        )
        finishNowButton = makeSecondaryButton(
            title: "Finish",
            image: UIImage(systemName: "checkmark.circle"),
            identifier: "roomScanner_button_done",
            action: #selector(finishNowTapped)
        )
        scanNextButton = makePrimaryButton(
            title: "Scan Next Room",
            image: UIImage(systemName: "camera.viewfinder"),
            identifier: "roomScanner_button_scanNext",
            action: #selector(scanNextTapped)
        )
        buildBlueprintButton = makeSecondaryButton(
            title: "Finish & Build",
            image: UIImage(systemName: "checkmark.circle.fill"),
            identifier: "roomScanner_button_buildBlueprint",
            action: #selector(buildBlueprintTapped)
        )
        cancelButton = makeSecondaryButton(
            title: "Cancel",
            image: nil,
            identifier: "roomScanner_button_cancelScan",
            action: #selector(cancelTapped)
        )

        for button in [nextRoomButton, finishNowButton, scanNextButton, buildBlueprintButton, cancelButton] {
            guard let button else { continue }
            view.addSubview(button)
        }

        NSLayoutConstraint.activate([
            // Status container — top
            statusContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusContainer.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
            statusLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -16),
            statusSubtitleLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            statusSubtitleLabel.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 16),
            statusSubtitleLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -16),
            statusSubtitleLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor, constant: -10),

            // Primary bottom-right
            nextRoomButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            nextRoomButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            nextRoomButton.heightAnchor.constraint(equalToConstant: 48),
            nextRoomButton.widthAnchor.constraint(equalToConstant: 150),

            scanNextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            scanNextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scanNextButton.heightAnchor.constraint(equalToConstant: 48),
            scanNextButton.widthAnchor.constraint(equalToConstant: 180),

            // Secondary bottom-center
            finishNowButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            finishNowButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            finishNowButton.heightAnchor.constraint(equalToConstant: 48),
            finishNowButton.widthAnchor.constraint(equalToConstant: 110),

            buildBlueprintButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            buildBlueprintButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            buildBlueprintButton.heightAnchor.constraint(equalToConstant: 48),
            buildBlueprintButton.widthAnchor.constraint(equalToConstant: 170),

            // Cancel bottom-left
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.heightAnchor.constraint(equalToConstant: 48),
            cancelButton.widthAnchor.constraint(equalToConstant: 100),
        ])
    }

    private func makePrimaryButton(title: String, image: UIImage?, identifier: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = image
        config.imagePadding = 6
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        button.accessibilityIdentifier = identifier
        return button
    }

    private func makeSecondaryButton(title: String, image: UIImage?, identifier: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.title = title
        config.image = image
        config.imagePadding = 6
        config.baseBackgroundColor = UIColor.darkGray.withAlphaComponent(0.7)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        button.accessibilityIdentifier = identifier
        return button
    }

    // MARK: - Phase application

    private func applyPhase(_ newPhase: Phase) {
        let count = viewModel?.roomsCapturedCount ?? 0
        let suffix = count == 1 ? "room" : "rooms"

        switch newPhase {
        case .capturing:
            nextRoomButton.isHidden = false
            finishNowButton.isHidden = false
            scanNextButton.isHidden = true
            buildBlueprintButton.isHidden = true
            cancelButton.isHidden = false
            statusLabel.text = count == 0 ? "Scanning Room 1" : "Scanning Room \(count + 1)"
            statusSubtitleLabel.text = count == 0
                ? "Walk the walls to map the room. Tap Next Room at a doorway."
                : "\(count) \(suffix) captured so far"
        case .betweenRooms:
            nextRoomButton.isHidden = true
            finishNowButton.isHidden = true
            scanNextButton.isHidden = false
            buildBlueprintButton.isHidden = false
            cancelButton.isHidden = false
            statusLabel.text = "\(count) \(suffix) captured"
            statusSubtitleLabel.text = "Walk to the next room and tap Scan Next Room, or tap Finish & Build."
        case .finishing:
            nextRoomButton.isHidden = true
            finishNowButton.isHidden = true
            scanNextButton.isHidden = true
            buildBlueprintButton.isHidden = true
            cancelButton.isHidden = true
            statusLabel.text = "Finishing scan…"
            statusSubtitleLabel.text = "Building your floor plan"
        }
    }

    private func setButtonsEnabled(_ enabled: Bool) {
        nextRoomButton.isEnabled = enabled
        finishNowButton.isEnabled = enabled
        scanNextButton.isEnabled = enabled
        buildBlueprintButton.isEnabled = enabled
        cancelButton.isEnabled = enabled
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
