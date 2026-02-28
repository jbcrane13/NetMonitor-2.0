import SwiftUI
import RoomPlan
import NetMonitorCore

// MARK: - RoomPlanScanView

/// Full-screen room scanning view powered by Apple's RoomPlan framework.
///
/// On LiDAR-equipped devices the user sees the live RoomPlan capture UI.
/// On completion the captured room is rendered to a scaled 2D floor plan
/// UIImage and a CalibrationScale derived from real-world dimensions.
/// On devices without LiDAR a graceful fallback is shown.
struct RoomPlanScanView: View {
    var onComplete: (UIImage?, CalibrationScale?) -> Void

    @State private var controller = RoomScanController()

    static var isSupported: Bool { RoomCaptureSession.isSupported }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if Self.isSupported {
                liveCapture
            } else {
                unsupportedView
            }
        }
        .statusBarHidden(true)
        .accessibilityIdentifier("screen_roomPlanScan")
        .onDisappear { controller.stopIfNeeded() }
        .onChange(of: controller.captureFinished) { _, finished in
            if finished { handleCompletion() }
        }
    }

    // MARK: - Live Capture

    private var liveCapture: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureLiveView(captureView: controller.captureView)
                .ignoresSafeArea()
                .onAppear { controller.start() }

            controlStrip
        }
        .overlay(alignment: .topTrailing) { closeButton }
    }

    private var controlStrip: some View {
        VStack(spacing: 12) {
            if !controller.captureFinished {
                Text("Slowly walk around the room to capture walls and openings")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Finish Scan") { controller.stop() }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 32).padding(.vertical, 14)
                    .background(Theme.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("roomplan_button_finish")
            } else {
                Label("Processing floor plan…", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                    .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    private var closeButton: some View {
        Button {
            controller.stopIfNeeded()
            onComplete(nil, nil)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(20)
        .accessibilityIdentifier("roomplan_button_close")
    }

    // MARK: - Unsupported Device

    private var unsupportedView: some View {
        VStack(spacing: 28) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52)).foregroundStyle(Theme.Colors.warning)
            VStack(spacing: 10) {
                Text("LiDAR Not Available")
                    .font(.title3).fontWeight(.bold).foregroundStyle(.white)
                Text("AR room scanning requires a LiDAR-equipped device\n(iPhone 12 Pro or later, iPad Pro M-series).\n\nUse Import or Freeform Grid instead.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Button("Go Back") { onComplete(nil, nil) }
                .fontWeight(.semibold)
                .padding(.horizontal, 36).padding(.vertical, 14)
                .background(Color.white.opacity(0.12))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("roomplan_button_unsupported_back")
        }
        .padding(40)
    }

    // MARK: - Completion

    private func handleCompletion() {
        guard let room = controller.capturedRoom else { onComplete(nil, nil)
        return
        }
        let result = RoomFloorPlanRenderer.render(room)
        onComplete(result?.image, result?.calibration)
    }
}

// MARK: - RoomScanController

@Observable
@MainActor
final class RoomScanController: NSObject, @unchecked Sendable {
    // RoomCaptureView owns the session; we read captureSession from it.
    let captureView: RoomCaptureView
    var captureFinished = false
    var capturedRoom: CapturedRoom?
    private var sessionDelegate: _RoomCaptureDelegate?

    override init() {
        captureView = RoomCaptureView(frame: .zero)
        super.init()
        let delegate = _RoomCaptureDelegate()
        delegate.owner = self
        sessionDelegate = delegate
        captureView.captureSession.delegate = delegate
    }

    func start() {
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    func stop() {
        captureView.captureSession.stop()
    }

    func stopIfNeeded() {
        stop()
    }
}

/// Separate NSObject for the delegate to satisfy `nonisolated` requirements.
private final class _RoomCaptureDelegate: NSObject, RoomCaptureSessionDelegate, @unchecked Sendable {
    weak var owner: RoomScanController?

    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didEndWith data: CapturedRoomData, error: Error?) {
        Task {
            let room = try? await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: data)
            await MainActor.run { [weak self] in
                self?.owner?.capturedRoom = room
                self?.owner?.captureFinished = true
            }
        }
    }

    nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {}
    nonisolated func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {}
    nonisolated func captureSession(_ session: RoomCaptureSession,
                                    didChange room: CapturedRoom) {}
    nonisolated func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) {}
}

// MARK: - RoomCaptureView Wrapper

private struct RoomCaptureLiveView: UIViewRepresentable {
    let captureView: RoomCaptureView

    func makeUIView(context: Context) -> RoomCaptureView { captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

// MARK: - Floor Plan Renderer

enum RoomFloorPlanRenderer {
    struct Result {
        let image: UIImage
        let calibration: CalibrationScale
    }

    static func render(_ room: CapturedRoom,
                       size: CGSize = CGSize(width: 1024, height: 1024)) -> Result? {
        guard !room.walls.isEmpty else { return nil }

        var minX = Float.infinity, maxX = -Float.infinity
        var minZ = Float.infinity, maxZ = -Float.infinity
        for wall in room.walls {
            let c = wall.transform.columns.3
            let hw = wall.dimensions.x / 2
            let hd = wall.dimensions.z / 2
            minX = Swift.min(minX, c.x - hw)
            maxX = Swift.max(maxX, c.x + hw)
            minZ = Swift.min(minZ, c.z - hd)
            maxZ = Swift.max(maxZ, c.z + hd)
        }

        let roomW = Double(maxX - minX)
        let roomD = Double(maxZ - minZ)
        guard roomW > 0, roomD > 0 else { return nil }

        let pad: CGFloat = 60
        let scale = Swift.min((size.width - pad * 2) / CGFloat(roomW),
                              (size.height - pad * 2) / CGFloat(roomD))
        let offX = (size.width  - CGFloat(roomW) * scale) / 2
        let offZ = (size.height - CGFloat(roomD) * scale) / 2

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            for wall in room.walls {
                let c = wall.transform.columns.3
                let cx = CGFloat(c.x - minX) * scale + offX
                let cz = CGFloat(c.z - minZ) * scale + offZ
                let hw = CGFloat(wall.dimensions.x / 2) * scale
                let hd = CGFloat(wall.dimensions.z / 2) * scale
                let rect = CGRect(x: cx - hw, y: cz - hd, width: hw * 2, height: hd * 2)
                UIColor(white: 0.85, alpha: 0.18).setFill()
                UIColor(white: 0.9, alpha: 1).setStroke()
                ctx.cgContext.setLineWidth(3)
                let path = UIBezierPath(rect: rect)
                path.fill()
                path.stroke()
            }
            UIColor(red: 0.13, green: 0.77, blue: 0.36, alpha: 0.9).setFill()
            for door in room.doors {
                let c = door.transform.columns.3
                let cx = CGFloat(c.x - minX) * scale + offX
                let cz = CGFloat(c.z - minZ) * scale + offZ
                let hw = CGFloat(door.dimensions.x / 2) * scale
                UIBezierPath(rect: CGRect(x: cx - hw, y: cz - 4, width: hw * 2, height: 8)).fill()
            }
            UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.8).setFill()
            for opening in room.openings {
                let c = opening.transform.columns.3
                let cx = CGFloat(c.x - minX) * scale + offX
                let cz = CGFloat(c.z - minZ) * scale + offZ
                let hw = CGFloat(opening.dimensions.x / 2) * scale
                UIBezierPath(rect: CGRect(x: cx - hw, y: cz - 3, width: hw * 2, height: 6)).fill()
            }
        }

        let longestReal = Swift.max(roomW, roomD)
        let longestPx = Double(longestReal == roomW ? CGFloat(roomW) * scale : CGFloat(roomD) * scale)
        let cal = CalibrationScale(pixelDistance: longestPx, realDistance: longestReal, unit: .meters)
        return Result(image: image, calibration: cal)
    }
}
