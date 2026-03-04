import NetMonitorCore
import SwiftUI

#if os(iOS) && !targetEnvironment(simulator)
import ARKit
import RealityKit
#endif

// MARK: - ContinuousScanView Subviews

extension ContinuousScanView {

    // MARK: - Start Scan View

    var startScanView: some View {
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

    var simulatorARPlaceholder: some View {
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

    var lidarRequiredView: some View {
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
                            "You can use Blueprint Import or AR Room Scan (with reduced precision) on this device."
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

    // MARK: - Post-Scan Transition

    var postScanTransitionView: some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.Colors.success)

            Text("Scan Complete")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)

            if let project = viewModel.completedProject {
                Text("\(project.measurementPoints.count) measurements collected")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Button {
                showPostScanReview = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.body.weight(.semibold))
                    Text("Review Results")
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                        .fill(Theme.Colors.accent)
                )
            }
            .accessibilityIdentifier("continuousScan_button_reviewResults")

            Button {
                dismiss()
            } label: {
                Text("Back to Dashboard")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityIdentifier("continuousScan_button_backAfterComplete")

            Spacer()
        }
        .themedBackground()
    }

    // MARK: - Refinement Progress View

    func refinementProgressView(progress: Double) -> some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            Spacer()

            ProgressView(value: progress) {
                Text("Refining Heatmap...")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .progressViewStyle(LinearProgressViewStyle(tint: Theme.Colors.accent))
            .padding(.horizontal, 48)

            Text("Applying full IDW interpolation for polished heatmap")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .themedBackground()
        .accessibilityIdentifier("continuousScan_refinementProgress")
    }

    // MARK: - Thermal Warning Banner

    func thermalWarningBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.sun.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)

                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.top, 48)

            Spacer()
        }
        .accessibilityIdentifier("continuousScan_thermalWarning")
    }

    // MARK: - Wi-Fi Degraded Banner

    var wifiDegradedBanner: some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.yellow)

                Text("Wi-Fi signal data paused — map continues updating")
                    .font(.caption2)
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 60)
        }
        .accessibilityIdentifier("continuousScan_wifiDegraded")
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
