import RoomPlan
import UIKit

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

        activateOverlayConstraints()
    }

    private func activateOverlayConstraints() {
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
