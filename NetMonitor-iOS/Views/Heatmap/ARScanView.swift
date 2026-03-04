import SwiftUI

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit
#endif

// MARK: - ARScanView

/// Phase 2 AR-Assisted Map Creation scan view.
///
/// Shows the AR camera feed with surface detection overlays (blue for walls,
/// green for floors), scan instructions, and device capability guidance.
/// Uses UIViewRepresentable to wrap ARView from RealityKit.
struct ARScanView: View {
    @State private var viewModel: ARScanViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ARScanViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? ARScanViewModel())
    }

    var body: some View {
        ZStack {
            if !viewModel.isARSupported {
                unsupportedDeviceView
            } else {
                arContentView
            }
        }
        .navigationTitle("AR Room Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    viewModel.stopScan()
                    dismiss()
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("arScan_button_cancel")
            }
        }
        .onDisappear {
            viewModel.stopScan()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
            if viewModel.cameraPermission == .denied || viewModel.cameraPermission == .restricted {
                Button("Open Settings") {
                    openAppSettings()
                }
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .accessibilityIdentifier("arScan_screen")
    }

    // MARK: - AR Content View

    private var arContentView: some View {
        ZStack {
            // AR Camera Feed
            arCameraView
                .ignoresSafeArea()

            // Overlay content
            VStack {
                // Instruction overlay at top
                if viewModel.isScanning || viewModel.sessionState == .idle {
                    scanInstructionOverlay
                        .padding(.top, 8)
                }

                Spacer()

                // Surface detection status
                if viewModel.isScanning {
                    surfaceDetectionStatus
                        .padding(.bottom, 8)
                }

                // Control buttons
                scanControlButtons
                    .padding(.bottom, 32)
            }

            // Non-LiDAR guidance banner
            if let guidance = viewModel.nonLiDARGuidanceText, viewModel.isScanning {
                VStack {
                    Spacer()
                        .frame(height: 80)
                    nonLiDARGuidanceBanner(guidance)
                    Spacer()
                }
            }
        }
    }

    // MARK: - AR Camera Feed

    @ViewBuilder
    private var arCameraView: some View {
        #if os(iOS) && !targetEnvironment(simulator)
        ARScanViewContainer(sessionManager: viewModel.arSessionManagerForView)
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
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(.gray.opacity(0.5))

                Text("AR Camera Preview")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text("AR is not available in the simulator.\nUse a physical device with ARKit support.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityIdentifier("arScan_simulatorPlaceholder")
    }

    // MARK: - Scan Instruction Overlay

    private var scanInstructionOverlay: some View {
        HStack(spacing: 12) {
            Image(systemName: instructionIconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(instructionIconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.instructionText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if viewModel.isLiDAR && viewModel.isScanning {
                    Text("LiDAR enabled — high precision scanning")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.Layout.screenPadding)
        .accessibilityIdentifier("arScan_instructionOverlay")
    }

    private var instructionIconName: String {
        switch viewModel.sessionState {
        case .idle:
            return "arrow.triangle.2.circlepath"
        case .running:
            if !viewModel.hasSurfacesDetected {
                return "viewfinder"
            }
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        default:
            return "camera.viewfinder"
        }
    }

    private var instructionIconColor: Color {
        switch viewModel.sessionState {
        case .running where viewModel.hasSurfacesDetected:
            return Theme.Colors.success
        case .error:
            return Theme.Colors.error
        default:
            return .cyan
        }
    }

    // MARK: - Surface Detection Status

    private var surfaceDetectionStatus: some View {
        HStack(spacing: 16) {
            surfaceBadge(
                icon: "rectangle.fill",
                label: "Walls",
                count: viewModel.wallCount,
                color: .blue
            )

            surfaceBadge(
                icon: "square.fill",
                label: "Floors",
                count: viewModel.floorCount,
                color: .green
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.Layout.screenPadding)
        .accessibilityIdentifier("arScan_surfaceStatus")
    }

    private func surfaceBadge(icon: String, label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text("\(label): \(count)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Non-LiDAR Guidance Banner

    private func nonLiDARGuidanceBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.body)
                .foregroundStyle(Theme.Colors.warning)

            Text(text)
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .padding(12)
        .background(Theme.Colors.warning.opacity(0.2))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Theme.Layout.screenPadding)
        .accessibilityIdentifier("arScan_nonLiDARGuidance")
    }

    // MARK: - Control Buttons

    private var scanControlButtons: some View {
        HStack(spacing: 16) {
            if viewModel.isScanning {
                // Stop button
                Button {
                    viewModel.stopScan()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                            .font(.body.weight(.semibold))
                        Text("Stop Scan")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                            .fill(Theme.Colors.error)
                    )
                }
                .accessibilityIdentifier("arScan_button_stop")
            } else {
                // Start button
                Button {
                    Task {
                        await viewModel.startScan()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.body.weight(.semibold))
                        Text("Start Scan")
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                            .fill(Theme.Colors.accent)
                    )
                    .shadow(color: Theme.Colors.accent.opacity(0.4), radius: 8, y: 4)
                }
                .accessibilityIdentifier("arScan_button_start")
            }
        }
    }

    // MARK: - Unsupported Device View

    private var unsupportedDeviceView: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                Spacer()
                    .frame(height: 40)

                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.Colors.error.opacity(0.7))

                VStack(spacing: Theme.Layout.itemSpacing) {
                    Text("ARKit Not Supported")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    // swiftlint:disable:next line_length
                    Text("This device does not support ARKit world tracking. AR-assisted room scanning requires an iPhone or iPad with an A12 chip or later.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                        Label("Alternative Option", systemImage: "map.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        // swiftlint:disable:next line_length
                        Text("You can still create Wi-Fi surveys using the blueprint import method. Import a floor plan image and manually place measurement points.")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.body.weight(.semibold))
                                Text("Use Blueprint Import")
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
                        .accessibilityIdentifier("arScan_button_useBlueprintImport")
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
        }
        .themedBackground()
        .accessibilityIdentifier("arScan_unsupportedDevice")
    }

    // MARK: - Helpers

    private func openAppSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

// MARK: - ARScanViewContainer

#if os(iOS) && !targetEnvironment(simulator)
/// UIViewRepresentable wrapper for ARView from RealityKit for the heatmap scan.
struct ARScanViewContainer: UIViewRepresentable {
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
        ARScanView()
    }
}
