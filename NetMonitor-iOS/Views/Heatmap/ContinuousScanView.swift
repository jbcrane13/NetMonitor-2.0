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
///
/// When scan is complete, navigates to PostScanReviewView for full-screen
/// map review with zoom/pan, visualization picker, and share/export.
struct ContinuousScanView: View {
    @State var viewModel: ContinuousScanViewModel
    @State var showPostScanReview = false
    @Environment(\.dismiss) var dismiss

    init(viewModel: ContinuousScanViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? ContinuousScanViewModel())
    }

    var body: some View {
        ZStack {
            if !viewModel.isLiDARAvailable {
                lidarRequiredView
            } else if viewModel.isScanComplete {
                postScanTransitionView
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
                if !viewModel.isScanComplete {
                    Button("Cancel") {
                        Task { await viewModel.cancelScan() }
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("continuousScan_button_cancel")
                }
            }
        }
        .onDisappear {
            Task { await viewModel.cleanup() }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .navigationDestination(isPresented: $showPostScanReview) {
            if let project = viewModel.completedProject {
                PostScanReviewView(
                    project: project,
                    refinedHeatmapImage: viewModel.refinedHeatmapImage,
                    bssidTransitions: viewModel.bssidTransitions
                )
            }
        }
        .accessibilityIdentifier("continuousScan_screen")
    }

    // MARK: - Scan Content (Split-Screen)

    private var scanContentView: some View {
        GeometryReader { geometry in
            if viewModel.isScanning || viewModel.isPaused {
                splitScreenLayout(geometry: geometry)
            } else if case .refining(let progress) = viewModel.scanPhase {
                refinementProgressView(progress: progress)
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
            // Top 40%: AR camera feed
            ZStack {
                arCameraView
                    .frame(height: arHeight)
                    .clipped()
                if viewModel.isScanning, viewModel.userWorldPosition != nil {
                    arPositionDotOverlay
                }
            }
            .frame(height: arHeight)
            .accessibilityIdentifier("continuousScan_arView")

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)

            // Bottom 60%: 2D map with heatmap + controls
            ZStack {
                mapView.frame(height: mapHeight)
                floatingControlsOverlay
                if let warning = viewModel.thermalWarning {
                    thermalWarningBanner(message: warning)
                }
                if viewModel.isWiFiDegraded {
                    wifiDegradedBanner
                }
            }
            .frame(height: mapHeight)
            .accessibilityIdentifier("continuousScan_mapView")
        }
    }

    // MARK: - AR Camera Feed

    @ViewBuilder
    var arCameraView: some View {
        #if os(iOS) && !targetEnvironment(simulator)
        ContinuousScanARContainer(sessionManager: viewModel.arSessionManagerForView)
        #else
        simulatorARPlaceholder
        #endif
    }

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
            Theme.Colors.backgroundBase
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
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
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
                if viewModel.isScanning || viewModel.isPaused {
                    pauseResumeButton.padding(.leading, 12).padding(.top, 8)
                }
                Spacer()
                if viewModel.isScanning || viewModel.isPaused,
                   let rssi = viewModel.currentRSSI {
                    signalBadge(rssi: rssi).padding(.trailing, 12).padding(.top, 8)
                }
            }
            Spacer()
            HStack {
                if viewModel.isScanning || viewModel.isPaused {
                    statsDisplay.padding(.leading, 12).padding(.bottom, 12)
                }
                Spacer()
                if viewModel.isScanning || viewModel.isPaused {
                    finishScanButton.padding(.trailing, 12).padding(.bottom, 12)
                }
            }
            if !viewModel.isAutoCenter && viewModel.isScanning {
                HStack {
                    Spacer()
                    Button {
                        viewModel.enableAutoCenter()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill").font(.caption2)
                            Text("Re-center").font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.trailing, 12).padding(.bottom, 8)
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
                    floatingControlLabel(icon: "play.fill", text: "Resume", color: Theme.Colors.accent)
                }
                .accessibilityIdentifier("continuousScan_button_resume")
            } else {
                Button {
                    Task { await viewModel.pauseScan() }
                } label: {
                    floatingControlLabel(icon: "pause.fill", text: "Pause", color: .orange)
                }
                .accessibilityIdentifier("continuousScan_button_pause")
            }
        }
    }

    // MARK: - Signal Badge

    private func signalBadge(rssi: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: rssi >= -70 ? "wifi" : "wifi.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(rssi >= -50 ? .green : rssi >= -70 ? .yellow : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(rssi) dBm").font(.caption2).fontWeight(.bold).foregroundStyle(.white)
                if let ssid = viewModel.currentSSID {
                    Text(ssid).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("continuousScan_signalBadge")
    }

    // MARK: - Stats Display

    private var statsDisplay: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill").font(.caption2).foregroundStyle(.cyan)
                Text("\(viewModel.downsampledPointCount) pts")
                    .font(.caption2).fontWeight(.medium).foregroundStyle(.white)
            }
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3.fill").font(.caption2).foregroundStyle(.green)
                Text("\(Int(viewModel.coveragePercentage * 100))%")
                    .font(.caption2).fontWeight(.medium).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("continuousScan_statsDisplay")
    }

    // MARK: - Finish Scan Button

    private var finishScanButton: some View {
        Button {
            Task { await viewModel.finishScan() }
        } label: {
            floatingControlLabel(icon: "checkmark.circle.fill", text: "Finish", color: Theme.Colors.success)
        }
        .accessibilityIdentifier("continuousScan_button_finish")
    }

    // MARK: - Floating Control Label

    private func floatingControlLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.weight(.semibold))
            Text(text).font(.caption).fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                .fill(color.opacity(0.8))
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ContinuousScanView()
    }
}
