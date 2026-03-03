import SwiftUI
import NetMonitorCore

// MARK: - HeatmapFullScreenView

/// Full-screen heatmap presented via `.fullScreenCover`.
/// In portrait: controls float at bottom. In landscape: controls move to leading sidebar.
struct HeatmapFullScreenView: View {
    @Binding var points: [HeatmapDataPoint]
    let floorplanImage: UIImage?
    @Binding var colorScheme: HeatmapColorScheme
    @Binding var overlays: HeatmapDisplayOverlay
    let calibration: CalibrationScale?
    let isSurveying: Bool
    var onTap: ((CGPoint, CGSize) -> Void)?
    var onStopSurvey: (() -> Void)?
    var onDismiss: () -> Void

    // periphery:ignore
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if isLandscape {
                    HStack(spacing: 0) {
                        sidebarControls
                            .frame(width: 160)
                        canvas
                    }
                } else {
                    VStack(spacing: 0) {
                        canvas
                        bottomControls
                    }
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
    }

    // MARK: - Canvas

    private var canvas: some View {
        HeatmapCanvasView(
            points: points,
            floorplanImage: floorplanImage,
            colorScheme: colorScheme,
            overlays: overlays,
            calibration: calibration,
            isSurveying: isSurveying,
            onTap: onTap
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .accessibilityIdentifier("heatmap_fullscreen_button_close")
        }
    }

    // MARK: - Bottom controls (portrait)

    private var bottomControls: some View {
        HeatmapControlStrip(
            colorScheme: $colorScheme,
            overlays: $overlays,
            isSurveying: isSurveying,
            onStopSurvey: onStopSurvey
        )
        .background(.ultraThinMaterial)
    }

    // MARK: - Sidebar controls (landscape)

    private var sidebarControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("WiFi Heatmap")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.top, 20)

            Divider().opacity(0.2)

            // Scheme picker
            VStack(alignment: .leading, spacing: 6) {
                Text("SCHEME")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                    Button {
                        colorScheme = scheme
                    } label: {
                        HStack {
                            Text(scheme.displayName)
                                .font(.caption)
                                .foregroundStyle(colorScheme == scheme ? Theme.Colors.accent : .white.opacity(0.7))
                            Spacer()
                            if colorScheme == scheme {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Divider().opacity(0.2)

            // Overlay toggles
            VStack(alignment: .leading, spacing: 6) {
                Text("OVERLAYS")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                overlayRow("Dots", overlay: .dots)
                overlayRow("Contour", overlay: .contour)
                overlayRow("Dead Zones", overlay: .deadZones)
            }

            Spacer()

            if isSurveying {
                Button {
                    onStopSurvey?()
                } label: {
                    Label("Stop Survey", systemImage: "stop.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.error.opacity(0.2))
                        .foregroundStyle(Theme.Colors.error)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.bottom, 16)
                .accessibilityIdentifier("heatmap_fullscreen_button_stop")
            }
        }
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
    }

    private func overlayRow(_ label: String, overlay: HeatmapDisplayOverlay) -> some View {
        let active = overlays.contains(overlay)
        return Button {
            if active { overlays.remove(overlay) } else { overlays.insert(overlay) }
        } label: {
            HStack {
                Image(systemName: active ? "checkmark.square.fill" : "square")
                    .foregroundStyle(active ? Theme.Colors.accent : .white.opacity(0.4))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 2)
        }
    }
}
