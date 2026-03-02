import SwiftUI
import NetMonitorCore

// MARK: - ARViewContainer (iOS real-device only)

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit

private struct ARHeatmapViewContainer: UIViewRepresentable {
    let arSession: ARHeatmapSession

    func makeUIView(context: Context) -> ARView {
        arSession.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif

// MARK: - ARHeatmapSurveyView

/// Full-screen AR camera view for continuous WiFi heatmap scanning.
///
/// Shows the live camera feed with color-coded signal spheres placed
/// automatically as the user walks around. A floating HUD displays
/// real-time signal strength and point count.
struct ARHeatmapSurveyView: View {
    @State private var viewModel = ARHeatmapSurveyViewModel()
    var onComplete: (HeatmapSurvey?) -> Void

    @State private var scanPulse = false

    var body: some View {
        ZStack {
            if ARHeatmapSession.isSupported {
                arContent
            } else {
                unsupportedContent
            }
        }
        .statusBarHidden(true)
        .onAppear { viewModel.startScanning() }
        .onDisappear {
            if viewModel.isScanning { viewModel.stopScanning() }
        }
        .accessibilityIdentifier("screen_arHeatmapSurvey")
    }

    // MARK: - AR Camera Content

    @ViewBuilder
    private var arContent: some View {
        #if os(iOS) && !targetEnvironment(simulator)
        ZStack {
            ARHeatmapViewContainer(arSession: viewModel.arSession)
                .ignoresSafeArea()

            // Live heatmap overlay — builds in real time as user walks
            if !viewModel.liveHeatmapPoints.isEmpty {
                HeatmapCanvasView(
                    points: viewModel.liveHeatmapPoints,
                    floorplanImage: nil,
                    colorScheme: .thermal,
                    overlays: [.gradient, .dots],
                    calibration: nil,
                    isSurveying: true,
                    onTap: nil
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)
                .opacity(0.85)
            }

            VStack(spacing: 0) {
                // Top: Signal HUD + close button
                topBar
                    .padding(.top, 12)

                Spacer()

                // Bottom: Stats + Done button
                bottomBar
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        #else
        unsupportedContent
        #endif
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .top) {
            // Signal HUD
            signalHUD
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

            Spacer()

            // Close button
            Button {
                viewModel.stopScanning()
                onComplete(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityIdentifier("ar_heatmap_button_close")
        }
    }

    private var signalHUD: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.signalDBm > -70 ? "wifi" : "wifi.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(viewModel.signalColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.signalText)
                        .font(.system(.headline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(viewModel.signalColor)
                        .monospacedDigit()

                    Text(viewModel.signalLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let ssid = viewModel.ssid {
                HStack(spacing: 4) {
                    Image(systemName: "wifi.circle")
                        .font(.caption2)
                    Text(ssid)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 14) {
            // Live stats
            HStack(spacing: 0) {
                statCell(
                    value: viewModel.isScanning ? viewModel.signalText : "--",
                    label: "SIGNAL",
                    valueColor: viewModel.signalColor
                )
                hudDivider
                statCell(
                    value: "\(viewModel.pointCount)",
                    label: "POINTS",
                    valueColor: .white
                )
                hudDivider
                statCell(
                    value: viewModel.isScanning ? scanningStatus : "STOPPED",
                    label: "STATUS",
                    valueColor: viewModel.isScanning ? .green : .secondary
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

            // Done button
            Button {
                viewModel.stopScanning()
                let survey = viewModel.buildSurvey()
                onComplete(survey)
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isScanning {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .opacity(scanPulse ? 1 : 0.3)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                       value: scanPulse)
                    }
                    Text(viewModel.pointCount > 0 ? "Done" : "Cancel")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(viewModel.pointCount > 0 ? Theme.Colors.accent : Color.white.opacity(0.12))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
            }
            .accessibilityIdentifier("ar_heatmap_button_done")
            .onAppear { scanPulse = true }
        }
    }

    private var scanningStatus: String {
        viewModel.pointCount == 0 ? "WAITING" : "SCANNING"
    }

    private var hudDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 44)
    }

    private func statCell(value: String, label: String, valueColor: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1.2)
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Unsupported Device Fallback

    private var unsupportedContent: some View {
        ZStack {
            Theme.Colors.backgroundBase.ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.Colors.warning)

                VStack(spacing: 10) {
                    Text("AR Not Available")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("Continuous AR scanning requires a device with\nARKit world tracking support.\n\nUse Freeform or Floorplan mode instead.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                Button {
                    onComplete(nil)
                } label: {
                    Text("Go Back")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("ar_heatmap_button_unsupported_back")
            }
            .padding(40)
        }
    }
}
