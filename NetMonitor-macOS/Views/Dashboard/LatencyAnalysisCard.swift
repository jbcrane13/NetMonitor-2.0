import SwiftUI
import NetMonitorCore

/// Row B (right): Latency histogram + stats from MonitoringSession.
struct LatencyAnalysisCard: View {
    let session: MonitoringSession?

    private var stats: LatencyStats {
        let latencies = session?.latestResults.values.compactMap(\.latency) ?? []
        return latencies.isEmpty
            ? LatencyStats(latencies: simulatedLatencies)
            : LatencyStats(latencies: latencies)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.success).frame(width: 5, height: 5)
                Text("LATENCY ANALYSIS · GATEWAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
            }

            // Histogram
            histogramView

            // Legend
            HStack(spacing: 10) {
                legendItem(color: MacTheme.Colors.success, label: "<5ms")
                legendItem(color: MacTheme.Colors.info,    label: "5–20ms")
                legendItem(color: MacTheme.Colors.warning, label: "20–50ms")
                legendItem(color: MacTheme.Colors.error,   label: ">50ms")
            }

            // Stats divider + row
            Divider().background(Color.white.opacity(0.06))
            HStack(spacing: 14) {
                statCell(value: formatMs(stats.avg),    label: "Avg",    color: MacTheme.Colors.success)
                statCell(value: formatMs(stats.min),    label: "Min",    color: MacTheme.Colors.success)
                statCell(value: formatMs(stats.max),    label: "Max",    color: MacTheme.Colors.warning)
                statCell(value: formatMs(stats.jitter), label: "Jitter", color: MacTheme.Colors.success)
                statCell(value: "0.0%",                 label: "Loss",   color: MacTheme.Colors.success)
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 10)
        .accessibilityIdentifier("dashboard_card_latencyAnalysis")
    }

    // MARK: Sub-views

    private var histogramView: some View {
        let buckets = stats.histogramBuckets
        let heights = buckets.normalizedHeights
        let colors  = [MacTheme.Colors.success, MacTheme.Colors.info,
                       MacTheme.Colors.warning, MacTheme.Colors.error]
        return GeometryReader { g in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { bucket in
                    ForEach(0..<8, id: \.self) { bar in
                        let rawWidth = (g.size.width - 24) / 32
                        let barWidth = rawWidth.isFinite ? max(0, rawWidth) : 0
                        let rawHeight = g.size.height * CGFloat(heights[bucket]) * barVariation(bucket: bucket, bar: bar)
                        let barHeight = rawHeight.isFinite ? max(0, rawHeight) : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[bucket].opacity(0.85))
                            .frame(width: barWidth, height: barHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
        .frame(height: 44)
        .accessibilityLabel("Latency distribution histogram")
    }

    /// Deterministic per-bar height variation — no Double.random at render time.
    private func barVariation(bucket: Int, bar: Int) -> CGFloat {
        let seed = UInt64(bucket &* 17 &+ bar &* 31 &+ 1)
        let x = (seed &* 6364136223846793005 &+ 1442695040888963407) >> 33
        return 0.6 + CGFloat(x) / CGFloat(UInt32.max) * 0.4
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func statCell(value: String?, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value ?? "—")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
                .textCase(.uppercase)
        }
    }

    private func formatMs(_ v: Double?) -> String? {
        v.map { String(format: $0 < 10 ? "%.1fms" : "%.0fms", $0) }
    }

    /// Deterministic simulated latency distribution for placeholder display.
    /// TODO: Replace with real historical measurements from SwiftData.
    private var simulatedLatencies: [Double] {
        (0..<100).map { i in
            let seed = UInt64(i &* 37 &+ 1)
            let x = (seed &* 6364136223846793005 &+ 1442695040888963407) >> 33
            let r = Double(x) / Double(UInt32.max)
            return max(0.5, 2.4 + sin(Double(i) * 0.3) * 3 + r * 6)
        }
    }
}
