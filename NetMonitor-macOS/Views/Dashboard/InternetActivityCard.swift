import SwiftUI
import NetMonitorCore

/// Row A (left): Live bandwidth chart with download + upload sparklines.
struct InternetActivityCard: View {
    let session: MonitoringSession?
    let interfaceName: String

    @State private var bandwidth: BandwidthMonitorService

    init(session: MonitoringSession?, interfaceName: String = "en0") {
        self.session = session
        self.interfaceName = interfaceName
        _bandwidth = State(initialValue: BandwidthMonitorService(interfaceName: interfaceName))
    }

    private var downloadHistory: [Double] { bandwidth.downloadHistory }
    private var uploadHistory: [Double]   { bandwidth.uploadHistory }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle()
                    .fill(MacTheme.Colors.info)
                    .frame(width: 5, height: 5)
                Text("INTERNET ACTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                    .textCase(.uppercase)

                Spacer()

                HStack(spacing: 14) {
                    Text("↓ \(BandwidthMonitorService.formatMbps(bandwidth.downloadMbps))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.Colors.info)
                        .accessibilityIdentifier("dashboard_activity_downloadSpeed")
                    Text("↑ \(BandwidthMonitorService.formatMbps(bandwidth.uploadMbps))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "8B5CF6"))
                        .accessibilityIdentifier("dashboard_activity_uploadSpeed")
                }
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
            .accessibilityLabel("Bandwidth activity chart")

            // Stats row
            HStack(spacing: 18) {
                statItem(
                    value: BandwidthMonitorService.formatBytes(bandwidth.sessionDownBytes),
                    label: "↓ SESSION",
                    color: MacTheme.Colors.info
                )
                statItem(
                    value: BandwidthMonitorService.formatBytes(bandwidth.sessionUpBytes),
                    label: "↑ SESSION",
                    color: Color(hex: "8B5CF6")
                )
                Spacer()
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 12)
        .accessibilityIdentifier("dashboard_card_internetActivity")
        .task(priority: .utility) { await bandwidth.start() }
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
}
