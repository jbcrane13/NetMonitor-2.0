import SwiftUI
import NetMonitorCore

// MARK: - ARViewRepresentable

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit

private struct ARViewRepresentable: UIViewRepresentable {
    let session: ARContinuousHeatmapSession
    func makeUIView(context: Context) -> ARView { session.arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif

// MARK: - ARContinuousHeatmapView

/// Full-screen WiFi Man-style continuous heatmap.
///
/// Layout (portrait):
///   - Top bar: ✕  "Signal Strength"  [Done]  +  SSID below title
///   - Full-screen AR camera feed with floor grid rendered by ARKit
///   - Bottom: dBm color scale strip (GlassCard)
///   - Bottom: AP info bar — SSID, BSSID, dBm, band (GlassCard)
struct ARContinuousHeatmapView: View {
    @State private var viewModel = ARContinuousHeatmapViewModel()
    var onComplete: (HeatmapSurvey?) -> Void

    var body: some View {
        ZStack {
            if ARContinuousHeatmapSession.isSupported {
                arContent
            } else {
                unsupportedContent
            }
        }
        .statusBarHidden(true)
        .ignoresSafeArea()
        .onAppear { viewModel.startScanning() }
        .onDisappear {
            if viewModel.isScanning { viewModel.stopScanning() }
        }
        .accessibilityIdentifier("screen_arContinuousHeatmap")
    }

    // MARK: - AR Content

    @ViewBuilder
    private var arContent: some View {
        #if os(iOS) && !targetEnvironment(simulator)
        ZStack(alignment: .bottom) {
            // Camera feed
            ARViewRepresentable(session: viewModel.session)
                .ignoresSafeArea()

            // Status overlay (shown while waiting for floor)
            if !viewModel.floorDetected {
                statusOverlay
            }

            // Bottom chrome
            VStack(spacing: 0) {
                Spacer()
                colorScaleStrip
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                apInfoBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
            }
        }
        .overlay(alignment: .top) {
            topBar
                .padding(.top, 56)
                .padding(.horizontal, 16)
        }
        #else
        // Simulator: show a dark placeholder with the overlay chrome
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            Text("AR not available in Simulator")
                .foregroundStyle(.white.opacity(0.4))

            VStack(spacing: 0) {
                Spacer()
                colorScaleStrip.padding(.horizontal, 12).padding(.bottom, 6)
                apInfoBar.padding(.horizontal, 12).padding(.bottom, 20)
            }
        }
        .overlay(alignment: .top) {
            topBar.padding(.top, 56).padding(.horizontal, 16)
        }
        #endif
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    viewModel.stopScanning()
                    onComplete(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityIdentifier("ar_continuous_button_close")

                Spacer()

                Text("Signal Strength")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    viewModel.stopScanning()
                    onComplete(viewModel.buildSurvey())
                } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 36)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityIdentifier("ar_continuous_button_done")
            }

            if let ssid = viewModel.ssid {
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                        .font(.caption2)
                    Text(ssid)
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    // MARK: - Status Overlay

    private var statusOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("ar_continuous_status_overlay")
    }

    // MARK: - Color Scale Strip

    /// Matches WiFi Man: "dBm  -80  -70  -60  -50  -40  -30" with red→green gradient
    private var colorScaleStrip: some View {
        HStack(spacing: 0) {
            Text("dBm")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.trailing, 6)

            GeometryReader { _ in
                ZStack(alignment: .leading) {
                    // Gradient bar
                    LinearGradient(
                        colors: [
                            Color(red: 0.8, green: 0, blue: 0),
                            Color(red: 1, green: 0.27, blue: 0),
                            Color(red: 1, green: 0.8, blue: 0),
                            Color(red: 0.53, green: 1, blue: 0),
                            Color(red: 0, green: 0.87, blue: 0.27),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                    // Tick labels
                    HStack(spacing: 0) {
                        ForEach([-80, -70, -60, -50, -40, -30], id: \.self) { val in
                            Text("\(val)")
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .offset(y: 14)
                }
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("ar_continuous_color_scale")
    }

    // MARK: - AP Info Bar

    private var apInfoBar: some View {
        HStack(spacing: 14) {
            // AP icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // SSID + BSSID
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.ssid ?? "—")
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(viewModel.bssid ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            // Signal + band
            VStack(alignment: .trailing, spacing: 3) {
                Text(viewModel.signalText)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(viewModel.signalColor)
                    .monospacedDigit()
                if let band = viewModel.band {
                    Text(band)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("ar_continuous_ap_info_bar")
    }

    // MARK: - Unsupported Fallback

    private var unsupportedContent: some View {
        ZStack {
            Theme.Colors.backgroundBase.ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.Colors.warning)
                VStack(spacing: 10) {
                    Text("AR Not Available")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Continuous AR scanning requires ARKit world tracking.\nUse Freeform or Floorplan mode instead.")
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
                .accessibilityIdentifier("ar_continuous_button_unsupported_back")
            }
            .padding(40)
        }
    }
}
