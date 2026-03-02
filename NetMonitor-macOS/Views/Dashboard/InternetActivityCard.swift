import SwiftUI
import NetMonitorCore

/// Row A (left): 24H bandwidth chart with download + upload sparklines.
/// Data is simulated pending real bandwidth measurement wiring (TODO).
struct InternetActivityCard: View {
    let session: MonitoringSession?

    @State private var selectedRange: BandwidthRange = .h24
    @State private var downloadHistory: [Double] = []
    @State private var uploadHistory:   [Double] = []

    enum BandwidthRange: String, CaseIterable {
        case h24 = "24H", d7 = "7D", d30 = "30D"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle()
                    .fill(MacTheme.Colors.info)
                    .frame(width: 5, height: 5)
                Text("INTERNET ACTIVITY · \(selectedRange.rawValue)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                    .textCase(.uppercase)

                Spacer()

                HStack(spacing: 14) {
                    Text("↓ 921 Mbps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.Colors.info)
                        .accessibilityIdentifier("dashboard_activity_downloadSpeed")
                    Text("↑ 458 Mbps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "8B5CF6"))
                        .accessibilityIdentifier("dashboard_activity_uploadSpeed")
                }

                Picker("", selection: $selectedRange) {
                    ForEach(BandwidthRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .accessibilityIdentifier("dashboard_activity_rangePicker")
            }

            // Chart
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.28))
                if !downloadHistory.isEmpty {
                    HistorySparkline(
                        data: uploadHistory,
                        color: Color(hex: "8B5CF6"),
                        lineWidth: 1.5,
                        showPulse: false
                    )
                    .opacity(0.7)
                    .overlay(alignment: .topLeading) {
                        HistorySparkline(
                            data: downloadHistory,
                            color: MacTheme.Colors.info,
                            lineWidth: 2,
                            showPulse: true
                        )
                    }
                    .padding(6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Bandwidth activity chart, \(selectedRange.rawValue) view")

            // Stats row
            HStack(spacing: 18) {
                statItem(value: "5.2 TB",  label: "↓ 24h total", color: MacTheme.Colors.info)
                statItem(value: "1.8 TB",  label: "↑ 24h total", color: Color(hex: "8B5CF6"))
                statItem(value: "7.0 TB",  label: "combined",    color: .white)
                Spacer()
                statItem(value: "99.8%",   label: "ISP uptime",  color: MacTheme.Colors.success)
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 12)
        .accessibilityIdentifier("dashboard_card_internetActivity")
        .onAppear { generateHistory() }
        .onChange(of: selectedRange) { _, _ in generateHistory() }
    }

    // MARK: Helpers

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .textCase(.uppercase)
        }
    }

    /// Deterministic seeded series so values don't change on every re-render.
    /// TODO: Replace with real bandwidth measurements from MonitoringSession.
    private func generateHistory() {
        let count = 60
        var dl: [Double] = []
        var ul: [Double] = []
        var seed: UInt64 = 42 &+ UInt64(selectedRange.rawValue.hashValue & 0xFFFF)
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt32.max)
        }
        for i in 0..<count {
            dl.append(max(200, 921 + sin(Double(i) * 0.25) * 60 + (next() - 0.5) * 130))
            ul.append(max(100, 458 + sin(Double(i) * 0.28) * 40 + (next() - 0.5) * 80))
        }
        downloadHistory = dl
        uploadHistory   = ul
    }
}
