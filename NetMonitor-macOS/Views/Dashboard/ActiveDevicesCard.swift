//
//  ActiveDevicesCard.swift
//  NetMonitor
//
//  Created by Claude on 2026-02-26.
//

import SwiftUI
import NetMonitorCore
import SwiftData

/// Row C (right): Online targets sorted by latency as device proxy.
/// TODO: Replace with real device discovery results when surfaced to dashboard.
struct ActiveDevicesCard: View {
    let session: MonitoringSession?

    @Query private var targets: [NetworkTarget]

    private var deviceRows: [(target: NetworkTarget, latency: Double?)] {
        targets
            .filter { session?.latestMeasurement(for: $0.id)?.isReachable == true }
            .sorted {
                let la = session?.latestMeasurement(for: $0.id)?.latency ?? .greatestFiniteMagnitude
                let lb = session?.latestMeasurement(for: $1.id)?.latency ?? .greatestFiniteMagnitude
                return la < lb
            }
            .prefix(5)
            .map { ($0, session?.latestMeasurement(for: $0.id)?.latency) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.warning).frame(width: 5, height: 5)
                Text("ACTIVE DEVICES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                Text("\(session?.onlineTargetCount ?? 0) online")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MacTheme.Colors.warning)
            }

            if deviceRows.isEmpty {
                Text("No devices online")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 3) {
                    ForEach(deviceRows, id: \.target.id) { item in
                        deviceRow(target: item.target, latency: item.latency)
                    }
                }
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 10)
        .accessibilityIdentifier("dashboard_card_activeDevices")
    }

    private func deviceRow(target: NetworkTarget, latency: Double?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(MacTheme.Colors.success)
                .frame(width: 5, height: 5)
                .shadow(color: MacTheme.Colors.success.opacity(0.6), radius: 2)
            Text(target.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer()
            Text(target.host)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            if let lat = latency {
                Text(String(format: lat < 10 ? "%.1fms" : "%.0fms", lat))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MacTheme.Colors.latencyColor(ms: lat))
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(Color.black.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("dashboard_device_\(target.host)")
    }
}
