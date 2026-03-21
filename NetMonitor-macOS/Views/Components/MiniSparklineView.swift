//
//  MiniSparklineView.swift
//  NetMonitor-macOS
//
//  Unified sparkline component for consistent mini-charts across all dashboard cards.
//  Wraps NetMonitorCore's HistorySparkline with a standard dark recessed container,
//  optional threshold coloring, and configurable display.
//

import SwiftUI
import NetMonitorCore

/// A reusable mini sparkline chart with a dark recessed container.
///
/// Provides a consistent visual language across all dashboard cards.
/// Wraps `HistorySparkline` from NetMonitorCore with:
/// - Standard dark rounded-rect container
/// - Optional threshold-based line coloring
/// - Configurable height, corner radius, padding
///
/// Usage:
/// ```swift
/// MiniSparklineView(data: latencyHistory, color: .blue)
/// MiniSparklineView(data: latencyHistory, thresholdColor: MacTheme.Colors.latencyColor)
/// ```
struct MiniSparklineView: View {
    let data: [Double]
    let color: Color
    let lineWidth: CGFloat
    let showPulse: Bool
    let height: CGFloat
    let cornerRadius: CGFloat

    /// Optional overlay sparkline (e.g., upload behind download)
    var overlayData: [Double]?
    var overlayColor: Color?
    var overlayLineWidth: CGFloat?

    /// Optional threshold-based coloring: given the latest value, returns a color.
    /// When provided, overrides the static `color` for the main sparkline.
    var thresholdColor: ((Double) -> Color)?

    init(
        data: [Double],
        color: Color = MacTheme.Colors.info,
        lineWidth: CGFloat = 1.5,
        showPulse: Bool = true,
        height: CGFloat = 34,
        cornerRadius: CGFloat = 6,
        overlayData: [Double]? = nil,
        overlayColor: Color? = nil,
        overlayLineWidth: CGFloat? = nil,
        thresholdColor: ((Double) -> Color)? = nil
    ) {
        self.data = data
        self.color = color
        self.lineWidth = lineWidth
        self.showPulse = showPulse
        self.height = height
        self.cornerRadius = cornerRadius
        self.overlayData = overlayData
        self.overlayColor = overlayColor
        self.overlayLineWidth = overlayLineWidth
        self.thresholdColor = thresholdColor
    }

    private var resolvedColor: Color {
        if let thresholdColor, let last = data.last {
            return thresholdColor(last)
        }
        return color
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.28))

            if data.count > 1 {
                // Overlay sparkline (behind main)
                if let overlayData, let overlayColor, overlayData.count > 1 {
                    HistorySparkline(
                        data: overlayData,
                        color: overlayColor,
                        lineWidth: overlayLineWidth ?? (lineWidth * 0.8),
                        showPulse: false
                    )
                    .opacity(0.7)
                    .padding(4)
                }

                // Main sparkline
                HistorySparkline(
                    data: data,
                    color: resolvedColor,
                    lineWidth: lineWidth,
                    showPulse: showPulse
                )
                .padding(4)
            } else {
                // Empty/waiting state — subtle baseline
                GeometryReader { g in
                    Path { path in
                        let y = g.size.height / 2
                        path.move(to: CGPoint(x: 4, y: y))
                        path.addLine(to: CGPoint(x: g.size.width - 4, y: y))
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Sparkline chart")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("MiniSparklineView") {
    VStack(spacing: 16) {
        // Basic
        MiniSparklineView(
            data: [5.2, 8.1, 3.4, 12.0, 7.5, 4.2, 9.8, 6.1],
            color: MacTheme.Colors.info
        )

        // With threshold coloring
        MiniSparklineView(
            data: [5.2, 8.1, 23.4, 52.0, 17.5, 4.2, 9.8, 6.1],
            thresholdColor: { ms in
                switch ms {
                case ..<5:   return MacTheme.Colors.success
                case 5..<20: return MacTheme.Colors.info
                case 20..<50: return MacTheme.Colors.warning
                default:     return MacTheme.Colors.error
                }
            }
        )

        // Dual overlay (download + upload)
        MiniSparklineView(
            data: [80, 95, 72, 88, 100, 110, 98],
            color: MacTheme.Colors.info,
            overlayData: [20, 25, 18, 22, 30, 28, 24],
            overlayColor: Color(hex: "8B5CF6")
        )

        // Empty state
        MiniSparklineView(data: [], color: MacTheme.Colors.info)
    }
    .frame(width: 300)
    .padding()
    .background(MacTheme.Colors.backgroundBase)
}
#endif
