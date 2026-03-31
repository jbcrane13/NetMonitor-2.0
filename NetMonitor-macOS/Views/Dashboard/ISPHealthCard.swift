//
//  ISPHealthCard.swift
//  NetMonitor
//
//  Created by Claude on 2026-02-26.
//

import SwiftUI
import NetMonitorCore

/// Row B (left): Compact ISP info card — name, public IP, uptime bar, speeds, mini chart.
struct ISPHealthCard: View {
    let interfaceName: String

    @State private var vm: ISPCardViewModel
    @State private var bandwidth: BandwidthMonitorService
    @State private var showHistory = false

    var gatewayAddress: String = "—"
    var resolvedDomain: String? = nil

    /// Real uptime data computed from persisted connectivity history.
    /// Nil until the parent view has initialized `UptimeViewModel`.
    var uptime: UptimeViewModel? = nil

    init(
        interfaceName: String = "en0",
        gatewayAddress: String = "—",
        resolvedDomain: String? = nil,
        uptime: UptimeViewModel? = nil,
        service: any ISPLookupServiceProtocol = ISPLookupService()
    ) {
        self.interfaceName = interfaceName
        self.gatewayAddress = gatewayAddress
        self.resolvedDomain = resolvedDomain
        self.uptime = uptime
        _vm = State(initialValue: ISPCardViewModel(service: service))
        _bandwidth = State(initialValue: BandwidthMonitorService(interfaceName: interfaceName))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Card fills available height when placed in a sized container
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.success).frame(width: 5, height: 5)
                Text("GATEWAY HEALTH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(uptime == nil)
                .accessibilityIdentifier("ispHealth_button_history")
                Text("GATEWAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MacTheme.Colors.success)
                    .tracking(1)
            }

            if vm.isLoading {
                CardLoadingSkeleton(showChart: true, lineCount: 3)
                    .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    // Left: ISP details
                    VStack(alignment: .leading, spacing: 3) {
                        Text(gatewayAddress)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                        if let domain = resolvedDomain {
                            Text(domain)
                                .font(.system(size: 11))
                                .foregroundStyle(MacTheme.Colors.info)
                                .lineLimit(1)
                        }
                        if let ip = vm.ispInfo?.publicIP {
                            HStack(spacing: 4) {
                                Text("WAN")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                Text(ip)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        uptimeBarView
                        HStack(spacing: 16) {
                            speedLabel("↓", value: BandwidthMonitorService.formatMbps(bandwidth.downloadMbps), color: MacTheme.Colors.info)
                            speedLabel("↑", value: BandwidthMonitorService.formatMbps(bandwidth.uploadMbps), color: Color(hex: "8B5CF6"))
                        }
                    }
                    Spacer()
                    // Right: Uptime summary — real data when available, placeholder otherwise.
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("30-DAY UPTIME")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        if let pct = uptime?.uptimePct {
                            Text(String(format: "%.1f%%", pct))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    pct > 99 ? MacTheme.Colors.success :
                                    pct > 95 ? MacTheme.Colors.warning :
                                    MacTheme.Colors.error
                                )
                            Text("\(uptime?.outageCount ?? 0) outage\(uptime?.outageCount == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("No history yet")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Throughput sparkline — expands to fill remaining card height
                MiniSparklineView(
                    data: bandwidth.downloadHistory,
                    color: MacTheme.Colors.info,
                    lineWidth: 1.5,
                    showPulse: true,
                    height: 60,
                    overlayData: bandwidth.uploadHistory,
                    overlayColor: Color(hex: "8B5CF6"),
                    overlayLineWidth: 1.2
                )
                .frame(minHeight: 60, maxHeight: .infinity)
                .accessibilityLabel("Live throughput chart")
            }

            if let errorMessage = vm.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
                    .accessibilityIdentifier("ispHealth_label_error")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .macGlassCard(cornerRadius: 14, padding: 10, statusGlow: MacTheme.Colors.info)
        .accessibilityIdentifier("dashboard_card_networkHealth")
        .task { await vm.load() }
        .task(priority: .utility) { await bandwidth.start() }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                UptimeHistoryView(profileID: uptime?.profileID ?? UUID())
            }
            .frame(minWidth: 600, minHeight: 500)
        }
    }

    // MARK: Sub-views

    private var uptimeBarView: some View {
        GeometryReader { g in
            let segments = uptime?.uptimeBar ?? []
            HStack(spacing: 1) {
                if segments.isEmpty {
                    // No history yet — render neutral gray placeholder capsules.
                    ForEach(0..<30, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.15))
                            .frame(
                                width: max(1, (g.size.width - 29) / 30)
                            )
                    }
                } else {
                    ForEach(0..<segments.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(segments[i]
                                  ? MacTheme.Colors.success.opacity(0.6)
                                  : MacTheme.Colors.error)
                            .frame(
                                width: max(1, (g.size.width - CGFloat(segments.count - 1)) / CGFloat(segments.count))
                            )
                    }
                }
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Network uptime history bar")
    }

    private func speedLabel(_ arrow: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(arrow).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
    }
}
