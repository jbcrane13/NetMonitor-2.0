import NetMonitorCore
import SwiftUI

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit
#endif

// MARK: - ContinuousScanView

/// Phase 3 AR Continuous Scan view.
///
/// Shows the AR camera feed with concurrent Wi-Fi measurement capture.
/// The pipeline runs in the background, collecting signal measurements
/// tagged with AR camera positions. The Metal rendering feature (separate worker)
/// will add the split-screen 2D map; this view provides the capture pipeline,
/// status overlays, and scan controls.
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

    // MARK: - Scan Content

    private var scanContentView: some View {
        ZStack {
            // AR camera feed
            arCameraView
                .ignoresSafeArea()

            // Status overlays
            VStack {
                // Status bar at top
                if viewModel.isScanning {
                    scanStatusBar
                        .padding(.top, 8)
                }

                Spacer()

                // Signal strength badge
                if viewModel.isScanning, let rssi = viewModel.currentRSSI {
                    signalBadge(rssi: rssi)
                        .padding(.bottom, 8)
                }

                // Controls at bottom
                scanControls
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - AR Camera Feed

    @ViewBuilder
    private var arCameraView: some View {
        #if os(iOS) && !targetEnvironment(simulator)
        ContinuousScanARContainer(sessionManager: viewModel.arSessionManagerForView)
        #else
        simulatorPlaceholder
        #endif
    }

    // MARK: - Simulator Placeholder

    private var simulatorPlaceholder: some View {
        ZStack {
            Theme.Colors.backgroundBase
                .ignoresSafeArea()

            VStack(spacing: Theme.Layout.sectionSpacing) {
                Image(systemName: "wave.3.forward.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.purple.opacity(0.5))

                Text("Continuous Scan")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text("AR Continuous Scan is not available in the simulator.\nUse a physical device with LiDAR.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityIdentifier("continuousScan_simulatorPlaceholder")
    }

    // MARK: - Scan Status Bar

    private var scanStatusBar: some View {
        HStack(spacing: 16) {
            // Measurement count
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.cyan)

                Text("\(viewModel.downsampledPointCount) pts")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }

            // Rate indicator
            HStack(spacing: 6) {
                Image(systemName: viewModel.isStationary ? "pause.circle.fill" : "waveform.circle.fill")
                    .font(.caption)
                    .foregroundStyle(viewModel.isStationary ? .orange : .green)

                let rateHz = 1.0 / viewModel.currentInterval
                Text(String(format: "%.1f Hz", rateHz))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }

            // Raw measurement count
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.blue)

                Text("\(viewModel.rawMeasurementCount) raw")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.Layout.screenPadding)
        .accessibilityIdentifier("continuousScan_statusBar")
    }

    // MARK: - Signal Badge

    private func signalBadge(rssi: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: signalIconName(rssi: rssi))
                .font(.body.weight(.semibold))
                .foregroundStyle(signalColor(rssi: rssi))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(rssi) dBm")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                if let ssid = viewModel.currentSSID {
                    Text(ssid)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.Layout.screenPadding)
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

    // MARK: - Scan Controls

    private var scanControls: some View {
        HStack(spacing: 16) {
            if viewModel.isScanning {
                if viewModel.isPaused {
                    // Resume button
                    Button {
                        Task { await viewModel.resumeScan() }
                    } label: {
                        controlLabel(icon: "play.fill", text: "Resume", color: Theme.Colors.accent)
                    }
                    .accessibilityIdentifier("continuousScan_button_resume")
                } else {
                    // Pause button
                    Button {
                        Task { await viewModel.pauseScan() }
                    } label: {
                        controlLabel(icon: "pause.fill", text: "Pause", color: .orange)
                    }
                    .accessibilityIdentifier("continuousScan_button_pause")
                }

                // Finish Scan button
                Button {
                    Task { await viewModel.finishScan() }
                } label: {
                    controlLabel(icon: "checkmark.circle.fill", text: "Finish Scan", color: Theme.Colors.success)
                }
                .accessibilityIdentifier("continuousScan_button_finish")
            } else {
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
            }
        }
    }

    private func controlLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
            Text(text)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                .fill(color.opacity(0.8))
        )
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
