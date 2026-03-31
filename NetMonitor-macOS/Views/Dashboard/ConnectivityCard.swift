//
//  ConnectivityCard.swift
//  NetMonitor
//
//  Created by Claude on 2026-02-26.
//

import SwiftUI
import NetMonitorCore

/// Row C (left): Public IP, gateway, DNS, anchor ping pills.
struct ConnectivityCard: View {
    let session:        MonitoringSession?
    let profileManager: NetworkProfileManager?

    @State private var vm: ConnectivityCardViewModel

    init(session: MonitoringSession?, profileManager: NetworkProfileManager?,
         ispService: any ISPLookupServiceProtocol = ISPLookupService()) {
        self.session = session
        self.profileManager = profileManager
        _vm = State(initialValue: ConnectivityCardViewModel(service: ispService))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Header
            HStack {
                Circle().fill(MacTheme.Colors.info).frame(width: 5, height: 5)
                Text("CONNECTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
            }

            // Two-column info grid
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: 4
            ) {
                connRow(key: "ISP",       value: vm.ispInfo?.isp ?? "—")
                connRow(key: "DNS",       value: vm.dnsServers)
                connRow(key: "Public IP", value: vm.ispInfo?.publicIP ?? "—",
                        mono: true, color: MacTheme.Colors.info)
                connRow(key: "IPv6",      value: vm.hasIPv6 ? "Enabled" : "Disabled",
                        color: vm.hasIPv6 ? MacTheme.Colors.success : .secondary)
                connRow(key: "Gateway",
                        value: profileManager?.activeProfile?.gatewayIP ?? "—",
                        mono: true)
                connRow(key: "Location",  value: locationString)
            }

            if let loadError = vm.loadError {
                Text(loadError)
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
                    .accessibilityIdentifier("connectivity_label_error")
            }

            // Anchor ping pills
            anchorPingsView
        }
        .macGlassCard(cornerRadius: 14, padding: 10, statusGlow: MacTheme.Colors.info)
        .accessibilityIdentifier("dashboard_card_connectivity")
        .task {
            await vm.load()
        }
    }

    // MARK: Sub-views

    private func connRow(
        key: String,
        value: String,
        mono: Bool = false,
        color: Color = .white
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(key.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Text(value)
                .font(mono
                      ? .system(size: 11, design: .monospaced)
                      : .system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private var anchorPingsView: some View {
        let anchors: [(name: String, host: String)] = [
            ("Google",     "8.8.8.8"),
            ("Cloudflare", "1.1.1.1"),
            ("AWS",        "52.94.236.248"),
            ("Apple",      "17.253.144.10"),
        ]
        return HStack(spacing: 6) {
            ForEach(anchors, id: \.name) { anchor in
                anchorPill(name: anchor.name, host: anchor.host)
            }
        }
    }

    private func anchorPill(name: String, host _: String) -> some View {
        // vm.anchorLatencies[name] is nil when not yet measured,
        // .some(nil) when unreachable, .some(latency) when live
        let latencyText: String = {
            guard let entry = vm.anchorLatencies[name] else { return "—" }
            guard let ms = entry else { return "✕" }
            return String(format: "%.0fms", ms)
        }()
        return HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(latencyText)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MacTheme.Colors.info)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(MacTheme.Colors.info.opacity(0.08))
        .overlay(Capsule().stroke(MacTheme.Colors.info.opacity(0.2), lineWidth: 0.5))
        .clipShape(Capsule())
        .accessibilityIdentifier("connectivity_label_ping\(name.lowercased())")
    }

    // MARK: Helpers

    private var locationString: String {
        if let city = vm.ispInfo?.city, let country = vm.ispInfo?.country {
            return "\(city), \(country)"
        }
        return vm.ispInfo?.country ?? "—"
    }
}
