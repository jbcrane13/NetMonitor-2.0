import SwiftUI

// MARK: - ARViewContainer (iOS real-device only)

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit

/// SwiftUI wrapper for `ARView` from RealityKit.
// periphery:ignore
private struct ARViewContainer: UIViewRepresentable {
    let arSession: ARWiFiSession

    func makeUIView(context: Context) -> ARView {
        arSession.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif

// MARK: - ARWiFiSignalView

/// Camera overlay showing real-time WiFi signal strength using AR.
///
/// On supported real devices: renders the live camera feed via ARKit/RealityKit with
/// a floating HUD. Users tap "Drop Anchor" to place a color-coded sphere for reference.
///
/// On unsupported devices or simulator: shows a static signal-strength dashboard.
// periphery:ignore
struct ARWiFiSignalView: View {
    @State private var viewModel = ARWiFiViewModel()

    var body: some View {
        ZStack {
            if viewModel.isARSupported {
                arOverlayContent
            } else {
                fallbackContent
            }
        }
        .navigationTitle("AR WiFi Signal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.startSession() }
        .onDisappear { viewModel.stopSession() }
    }

    // MARK: - AR Overlay (real device)

    @ViewBuilder
    private var arOverlayContent: some View {
        #if os(iOS) && !targetEnvironment(simulator)
        ZStack {
            ARViewContainer(arSession: viewModel.arSession)
                .ignoresSafeArea()

            VStack {
                signalHUD
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()

                Spacer()

                anchorButton
                    .padding(.bottom, 32)
            }
        }
        #else
        fallbackContent
        #endif
    }

    // MARK: - Fallback (simulator / unsupported device)

    private var fallbackContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !viewModel.isARSupported {
                    Label("AR not available on this device", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                signalHUD
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.059, green: 0.090, blue: 0.165),
                         Color(red: 0.118, green: 0.227, blue: 0.373)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Signal HUD

    private var signalHUD: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: signalIconName)
                    .font(.system(size: 36))
                    .foregroundStyle(viewModel.signalColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.signalDBm) dBm")
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(viewModel.signalColor)

                    Text(viewModel.signalLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ProgressView(value: viewModel.signalQuality)
                .tint(viewModel.signalColor)

            if let ssid = viewModel.ssid {
                Divider()
                HStack {
                    Label(ssid, systemImage: "wifi")
                        .font(.subheadline)
                    Spacer()
                    if let bssid = viewModel.bssid {
                        Text(bssid)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Place Anchor Button

    private var anchorButton: some View {
        Button(action: { viewModel.placeAnchor() }) {
            Label("Drop Signal Anchor", systemImage: "mappin.and.ellipse")
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(viewModel.signalColor.opacity(0.85))
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .shadow(radius: 8)
    }

    // MARK: - Helpers

    private var signalIconName: String {
        viewModel.signalDBm > -70 ? "wifi" : "wifi.exclamationmark"
    }
}
