import NetMonitorCore
import SwiftUI

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit
#endif

// MARK: - ContinuousScanView

/// Phase 3 AR Continuous Scan view with split-screen layout.
///
/// Top 40%: AR camera feed with walking path + surface overlays.
/// Bottom 60%: 2D map with heatmap coloring, position dot, pinch-to-zoom.
/// Floating controls: pause/resume, signal badge, stats, finish scan.
struct ContinuousScanView: View {
    @State private var viewModel: ContinuousScanViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ContinuousScanViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? ContinuousScanViewModel())
    }

    var body: some View {
        ZStack {
            if !viewModel.isLiDARAvailable {
                lidarRequiredView
            } else {
                scanContentView
            }
        }
        .navigationTitle("Continuous Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    Task {
                        await viewModel.cancelScan()
                    }
                    dismiss()
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("continuousScan_button_cancel")
            }
        }
        .onDisappear {
            Task {
                await viewModel.cleanup()
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .accessibilityIdentifier("continuousScan_screen")
    }

    // MARK: - Scan Content (Split-Screen)

    private var scanContentView: some View {
        GeometryReader { geometry in
            if viewModel.isScanning || viewModel.isScanComplete {
                splitScreenLayout(geometry: geometry)
            } else {
                startScanView
            }
        }
    }

    /// Split-screen: AR camera (top 40%) + 2D map with heatmap (bottom 60%).
    private func splitScreenLayout(geometry: GeometryProxy) -> some View {
        let arHeight = geometry.size.height * 0.4
        let mapHeight = geometry.size.height * 0.6

        return VStack(spacing: 0) {
            // Top 40%: AR camera feed with walking path + surface overlays
            ZStack {
                arCameraView
                    .frame(height: arHeight)
                    .clipped()

                // Position dot overlay on AR view
                if viewModel.isScanning, viewModel.userWorldPosition != nil {
                    arPositionDotOverlay
                }
            }
            .frame(height: arHeight)
            .accessibilityIdentifier("continuousScan_arView")

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)

            // Bottom 60%: 2D map with heatmap + position dot
            ZStack {
                mapView
                    .frame(height: mapHeight)

                // Floating controls overlay
                floatingControlsOverlay
            }
            .frame(height: mapHeight)
            .accessibilityIdentifier("continuousScan_mapView")
        }
    }

    // MARK: - AR Camera Feed

    @ViewBuilder
    private var arCameraView: some View {
        #if os(iOS) && !targetEnvironment(simulator)
        ContinuousScanARContainer(sessionManager: viewModel.arSessionManagerForView)
        #else
        simulatorARPlaceholder
        #endif
    }

    /// Pulsing position dot on the AR camera view.
    private var arPositionDotOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                PulsingDot(color: .blue, size: 16)
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
            }
        }
        .accessibilityIdentifier("continuousScan_arPositionDot")
    }

    // MARK: - 2D Map View

    private var mapView: some View {
        ZStack {
            // Dark grey background for unmapped areas
            Theme.Colors.backgroundBase

            // Map image with pinch-to-zoom
            if let mapImage = viewModel.mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(viewModel.mapScale)
                    .offset(viewModel.mapOffset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                viewModel.mapScale = max(0.5, min(5.0, scale))
                                viewModel.disableAutoCenter()
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                viewModel.mapOffset = value.translation
                                viewModel.disableAutoCenter()
                            }
                    )
                    .accessibilityIdentifier("continuousScan_mapImage")
            } else {
                // No map data yet
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            // Pulsing position dot on 2D map
            if viewModel.mapImage != nil, viewModel.userWorldPosition != nil {
                PulsingDot(color: .blue, size: 14)
                    .accessibilityIdentifier("continuousScan_mapPositionDot")
            }
        }
    }

    // MARK: - Floating Controls Overlay

    private var floatingControlsOverlay: some View {
        VStack {
            HStack {
                // Top-left: Pause/Resume
                if viewModel.isScanning {
                    pauseResumeButton
                        .padding(.leading, 12)
                        .padding(.top, 8)
                }

                Spacer()

                // Top-right: Signal strength badge
                if viewModel.isScanning, let rssi = viewModel.currentRSSI {
                    signalBadge(rssi: rssi)
                        .padding(.trailing, 12)
                        .padding(.top, 8)
                }
            }

            Spacer()

            HStack {
                // Bottom-left: Point count + coverage %
                if viewModel.isScanning {
                    statsDisplay
                        .padding(.leading, 12)
                        .padding(.bottom, 12)
                }

                Spacer()

                // Bottom-right: Finish scan
                if viewModel.isScanning && !viewModel.isPaused {
                    finishScanButton
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                }
            }

            // Auto-center toggle
            if !viewModel.isAutoCenter && viewModel.isScanning {
                HStack {
                    Spacer()
                    Button {
                        viewModel.enableAutoCenter()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                            Text("Re-center")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("continuousScan_button_recenter")
                }
            }
        }
    }

    // MARK: - Pause/Resume Button

    private var pauseResumeButton: some View {
        Group {
            if viewModel.isPaused {
                Button {
                    Task { await viewModel.resumeScan() }
                } label: {
                    floatingControlLabel(
                        icon: "play.fill",
                        text: "Resume",
                        color: Theme.Colors.accent
                    )
                }
                .accessibilityIdentifier("continuousScan_button_resume")
            } else {
                Button {
                    Task { await viewModel.pauseScan() }
                } label: {
                    floatingControlLabel(
                        icon: "pause.fill",
                        text: "Pause",
                        color: .orange
                    )
                }
                .accessibilityIdentifier("continuousScan_button_pause")
            }
        }
    }

    // MARK: - Signal Badge

    private func signalBadge(rssi: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: signalIconName(rssi: rssi))
                .font(.caption.weight(.semibold))
                .foregroundStyle(signalColor(rssi: rssi))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(rssi) dBm")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                if let ssid = viewModel.currentSSID {
                    Text(ssid)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("continuousScan_signalBadge")
    }

    private func signalIconName(rssi: Int) -> String {
        if rssi >= -50 { return "wifi" }
        if rssi >= -70 { return "wifi" }
        return "wifi.exclamationmark"
    }

    private func signalColor(rssi: Int) -> Color {
        if rssi >= -50 { return .green }
        if rssi >= -70 { return .yellow }
        return .red
    }

    // MARK: - Stats Display

    private var statsDisplay: some View {
        HStack(spacing: 10) {
            // Point count
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                Text("\(viewModel.downsampledPointCount) pts")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }

            // Coverage percentage
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("\(Int(viewModel.coveragePercentage * 100))%")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("continuousScan_statsDisplay")
    }

    // MARK: - Finish Scan Button

    private var finishScanButton: some View {
        Button {
            Task { await viewModel.finishScan() }
        } label: {
            floatingControlLabel(
                icon: "checkmark.circle.fill",
                text: "Finish",
                color: Theme.Colors.success
            )
        }
        .accessibilityIdentifier("continuousScan_button_finish")
    }

    // MARK: - Floating Control Label

    private func floatingControlLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                .fill(color.opacity(0.8))
        )
    }

    // MARK: - Start Scan View

    private var startScanView: some View {
        ZStack {
            // AR camera preview
            arCameraView
                .ignoresSafeArea()

            VStack {
                Spacer()

                // Start button
                Button {
                    Task { await viewModel.startScan() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wave.3.forward.circle.fill")
                            .font(.body.weight(.semibold))
                        Text("Start Continuous Scan")
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                            .fill(.purple)
                    )
                    .shadow(color: .purple.opacity(0.4), radius: 8, y: 4)
                }
                .accessibilityIdentifier("continuousScan_button_start")

                Spacer()
                    .frame(height: 60)
            }
        }
    }

    // MARK: - Simulator AR Placeholder

    private var simulatorARPlaceholder: some View {
        ZStack {
            Color(white: 0.15)

            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                    .foregroundStyle(.purple.opacity(0.5))
                Text("AR Camera")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .accessibilityIdentifier("continuousScan_simulatorPlaceholder")
    }

    // MARK: - LiDAR Required View

    private var lidarRequiredView: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                Spacer()
                    .frame(height: 40)

                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.Colors.error.opacity(0.7))

                VStack(spacing: Theme.Layout.itemSpacing) {
                    Text("LiDAR Required")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    // swiftlint:disable:next line_length
                    Text("Continuous scanning requires a device with LiDAR sensor for precise spatial mapping. This includes iPhone 12 Pro and later Pro models, and iPad Pro (2020) and later.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                        Label("Alternative Options", systemImage: "arrow.triangle.branch")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text(
                            "You can use Blueprint Import or AR Room Scan (with reduced precision) to create Wi-Fi coverage surveys on this device."
                        )
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.left")
                                    .font(.body.weight(.semibold))
                                Text("Back to Dashboard")
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                                    .fill(Theme.Colors.accent.opacity(0.15))
                            )
                        }
                        .accessibilityIdentifier("continuousScan_button_backToDashboard")
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
        }
        .themedBackground()
        .accessibilityIdentifier("continuousScan_lidarRequired")
    }
}

// MARK: - PulsingDot

/// A pulsing blue circle indicating the user's current position.
struct PulsingDot: View {
    let color: Color
    let size: CGFloat
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: size * 2, height: size * 2)
                .scaleEffect(isPulsing ? 1.5 : 1.0)
                .opacity(isPulsing ? 0.0 : 0.4)

            // Inner dot
            Circle()
                .fill(color)
                .frame(width: size, height: size)

            // White center highlight
            Circle()
                .fill(.white.opacity(0.5))
                .frame(width: size * 0.4, height: size * 0.4)
        }
        .onAppear {
            withAnimation(Theme.Animation.pulse) {
                isPulsing = true
            }
        }
    }
}

// MARK: - ContinuousScanARContainer

#if os(iOS) && !targetEnvironment(simulator)
/// UIViewRepresentable wrapper for ARView during continuous scanning.
struct ContinuousScanARContainer: UIViewRepresentable {
    let sessionManager: ARSessionManager

    func makeUIView(context: Context) -> ARView {
        sessionManager.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif

// MARK: - Preview

#Preview {
    NavigationStack {
        ContinuousScanView()
    }
}
