import SwiftUI
import NetMonitorCore

/// Row B (right): Rolling latency waveform + stats from MonitoringSession.
struct LatencyAnalysisCard: View {
    let session: MonitoringSession?
    var gatewayLatencyHistory: [Double] = []

    private var waveformData: [Double] {
        gatewayLatencyHistory
    }

    private var stats: LatencyStats {
        let latencies = waveformData.isEmpty
            ? (session?.latestResults.values.compactMap(\.latency) ?? [])
            : waveformData
        return LatencyStats(latencies: latencies)
    }

    /// Packet-loss string computed from the latest monitoring results.
    /// A target is considered "lost" when it is not reachable (timeout / error).
    private var packetLossString: String {
        guard let results = session?.latestResults, !results.isEmpty else { return "—" }
        let total = results.count
        let lost = results.values.filter { !$0.isReachable }.count
        let pct = Double(lost) / Double(total) * 100
        return String(format: "%.1f%%", pct)
    }

    private var currentLatency: Double? {
        waveformData.last
    }

    @State private var calibrationPhase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with current-value badge
            HStack {
                Circle().fill(MacTheme.Colors.success).frame(width: 5, height: 5)
                Text("LATENCY ANALYSIS \u{00B7} GATEWAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                if let ms = currentLatency {
                    HStack(spacing: 4) {
                        Text(formatMs(ms) ?? "")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(thresholdColor(ms: ms))
                        Circle()
                            .fill(thresholdColor(ms: ms))
                            .frame(width: 5, height: 5)
                    }
                }
            }

            // Rolling waveform
            waveformView

            // Gradient legend bar
            gradientLegend

            // Stats divider + row
            Divider().background(Color.white.opacity(0.06))
            HStack(spacing: 14) {
                statCell(value: formatMs(stats.avg), label: "AVG", ms: stats.avg)
                statCell(value: formatMs(stats.min), label: "MIN", ms: stats.min)
                statCell(value: formatMs(stats.max), label: "MAX", ms: stats.max)
                statCell(value: formatMs(stats.jitter), label: "JITTER", ms: stats.jitter)
                statCell(value: packetLossString, label: "LOSS", ms: 0)
                Spacer()
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 10, statusGlow: MacTheme.Colors.info)
        .accessibilityIdentifier("dashboard_card_latencyAnalysis")
    }

    // MARK: - Waveform

    private var waveformView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.28))

            GeometryReader { g in
                let data = waveformData
                if data.isEmpty {
                    calibratingView(size: g.size)
                } else if data.count > 1 {
                    let padding: CGFloat = 4
                    let w = g.size.width - padding * 2
                    let h = g.size.height - padding * 2

                    let rawMin = data.min() ?? 0
                    let rawMax = data.max() ?? 1
                    let rangePad = (rawMax - rawMin) * 0.1
                    let minVal = rawMin - rangePad
                    let maxVal = rawMax + rangePad
                    let range = maxVal - minVal == 0 ? 1 : maxVal - minVal

                    let stepX = w / CGFloat(data.count - 1)
                    let points: [CGPoint] = data.enumerated().map { i, val in
                        let normalizedVal = CGFloat((val - minVal) / range)
                        let y = padding + h - (normalizedVal * h)
                        let x = padding + CGFloat(i) * stepX
                        return CGPoint(x: x, y: y)
                    }

                    let lineColor = thresholdColor(ms: data.last ?? 0)

                    // Subtle grid lines at 25/50/75%
                    ForEach([0.25, 0.5, 0.75], id: \.self) { frac in
                        Path { path in
                            let y = padding + h - (CGFloat(frac) * h)
                            path.move(to: CGPoint(x: padding, y: y))
                            path.addLine(to: CGPoint(x: padding + w, y: y))
                        }
                        .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
                    }

                    // Gradient fill below line
                    Path { path in
                        addCatmullRomPath(to: &path, points: points)
                        path.addLine(to: CGPoint(x: points.last!.x, y: padding + h))
                        path.addLine(to: CGPoint(x: points.first!.x, y: padding + h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [lineColor.opacity(0.30), lineColor.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line stroke
                    Path { path in
                        addCatmullRomPath(to: &path, points: points)
                    }
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                    .shadow(color: lineColor.opacity(0.5), radius: 5)

                    // Pulse node at rightmost point
                    if let last = points.last {
                        Circle()
                            .fill(.white)
                            .frame(width: 4, height: 4)
                            .position(x: last.x, y: last.y)

                        Circle()
                            .stroke(lineColor, lineWidth: 1)
                            .frame(width: 9, height: 9)
                            .position(x: last.x, y: last.y)
                            .shadow(color: lineColor.opacity(0.6), radius: 4)
                    }
                }
            }
        }
        .frame(height: 60)
        // Animation removed — was causing layout loops inside parent containers
        .accessibilityLabel("Latency waveform chart")
    }

    // MARK: - Gradient Legend

    private var gradientLegend: some View {
        VStack(spacing: 2) {
            GeometryReader { g in
                let w = g.size.width
                LinearGradient(
                    stops: [
                        .init(color: MacTheme.Colors.success, location: 0),
                        .init(color: MacTheme.Colors.success, location: 0.15),
                        .init(color: MacTheme.Colors.info, location: 0.30),
                        .init(color: MacTheme.Colors.info, location: 0.45),
                        .init(color: MacTheme.Colors.warning, location: 0.60),
                        .init(color: MacTheme.Colors.warning, location: 0.75),
                        .init(color: MacTheme.Colors.error, location: 0.90),
                        .init(color: MacTheme.Colors.error, location: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 2)
                .clipShape(Capsule())
                .frame(width: w)
            }
            .frame(height: 2)

            HStack {
                Text("<5ms")
                Spacer()
                Text("5\u{2013}20ms")
                Spacer()
                Text("20\u{2013}50ms")
                Spacer()
                Text(">50ms")
            }
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.6))
        }
    }

    // MARK: - Sub-views

    private func statCell(value: String?, label: String, ms: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "\u{2014}")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(thresholdColor(ms: ms ?? 0))
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
        }
    }

    private func formatMs(_ v: Double?) -> String? {
        v.map { String(format: $0 < 10 ? "%.1fms" : "%.0fms", $0) }
    }

    private func thresholdColor(ms: Double) -> Color {
        switch ms {
        case ..<5:   return MacTheme.Colors.success
        case 5..<20: return MacTheme.Colors.info
        case 20..<50: return MacTheme.Colors.warning
        default:     return MacTheme.Colors.error
        }
    }

    // MARK: - Calibrating State

    private func calibratingView(size: CGSize) -> some View {
        let baselineOpacity = 0.08 + 0.07 * (1 + sin(calibrationPhase * 3)) / 2
        let scanX = 4 + (size.width - 8) * calibrationPhase.truncatingRemainder(dividingBy: 1.0)

        return ZStack {
            // Pulsing baseline
            Path { path in
                let y = size.height / 2
                path.move(to: CGPoint(x: 4, y: y))
                path.addLine(to: CGPoint(x: size.width - 4, y: y))
            }
            .stroke(Color.white.opacity(baselineOpacity), lineWidth: 1)

            // Scanning vertical line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [MacTheme.Colors.info.opacity(0), MacTheme.Colors.info.opacity(0.25), MacTheme.Colors.info.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2, height: size.height)
                .position(x: scanX, y: size.height / 2)
                .shadow(color: MacTheme.Colors.info.opacity(0.3), radius: 8)

            // Label
            Text("MEASURING\u{2026}")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.6))
                .tracking(2.0)
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                calibrationPhase = 1.0
            }
        }
    }

        // MARK: - Catmull-Rom

    private func addCatmullRomPath(to path: inout Path, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }

        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
    }

}
