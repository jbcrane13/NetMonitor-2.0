//
//  QuickStatsBar.swift
//  NetMonitor
//
//  Created by Claude on 1/28/26.
//

import SwiftUI
import NetMonitorCore

/// Displays real-time monitoring statistics in a horizontal bar
struct QuickStatsBar: View {
    @Environment(MonitoringSession.self) private var session: MonitoringSession?
    @Environment(\.appAccentColor) private var accentColor
    @Environment(\.compactMode) private var compactMode

    var body: some View {
        HStack(spacing: compactMode ? 12 : 20) {
            // Online count
            StatItem(
                icon: "checkmark.circle.fill",
                color: .green,
                label: "Online",
                value: "\(onlineCount)"
            )

            Divider()
                .frame(height: 20)

            // Offline count
            StatItem(
                icon: "xmark.circle.fill",
                color: .red,
                label: "Offline",
                value: "\(offlineCount)"
            )

            Divider()
                .frame(height: 20)

            // Average latency
            StatItem(
                icon: "clock.arrow.circlepath",
                color: accentColor,
                label: "Avg Latency",
                value: latencyString
            )

            Divider()
                .frame(height: 20)

            // Last check
            StatItem(
                icon: "clock.fill",
                color: .secondary,
                label: "Last Check",
                value: lastCheckString
            )
        }
        .padding(compactMode ? 8 : 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("dashboard_quickStats_bar")
    }

    // MARK: - Computed Properties

    private var onlineCount: Int {
        session?.latestResults.values.filter { $0.isReachable }.count ?? 0
    }

    private var offlineCount: Int {
        session?.latestResults.values.filter { !$0.isReachable }.count ?? 0
    }

    private var averageLatency: Double? {
        let latencies = session?.latestResults.values.compactMap { $0.latency } ?? []
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    private var latencyString: String {
        guard let avgLatency = averageLatency else {
            return "—"
        }
        return String(format: "%.1f ms", avgLatency)
    }

    private var lastCheckString: String {
        guard let latestTimestamp = session?.latestResults.values.map({ $0.timestamp }).max() else {
            return "—"
        }

        let interval = Date().timeIntervalSince(latestTimestamp)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
}

// MARK: - StatItem Helper View

private struct StatItem: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .imageScale(.medium)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.headline)
            }
        }
        .accessibilityIdentifier("dashboard_stat_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let container = PreviewContainer().container
    let context = container.mainContext
    let httpService = HTTPMonitorService()
    let icmpService = ICMPMonitorService()
    let tcpService = TCPMonitorService()
    let session = MonitoringSession(
        modelContext: context,
        httpService: httpService,
        icmpService: icmpService,
        tcpService: tcpService
    )

    QuickStatsBar()
        .padding()
        .modelContainer(container)
        .environment(session)
}
#endif
