import SwiftUI
import NetMonitorCore
import NetworkScanKit
import SwiftData

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    // periphery:ignore
    @State private var isAddNetworkSheetPresented = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Layout.itemSpacing) {
                    if !viewModel.isConnected {
                        OfflineBanner(lastScanDate: viewModel.lastScanDate)
                    }

                    TacticalHUDHeader(viewModel: viewModel)
                    
                    RefinedNetworkHealthCard(viewModel: viewModel)
                    
                    SignalEQView(viewModel: viewModel)
                    
                    SpeedTestQuickCard()

                    LiveEventTicker()

                    LocalDevicesCard(
                        viewModel: viewModel,
                        selectedNetwork: viewModel.activeNetwork
                    )
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.top, Theme.Layout.smallCornerRadius)
                .padding(.bottom, Theme.Layout.sectionSpacing)
            }
            .themedBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionStatusHeader(viewModel: viewModel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .accessibilityIdentifier("dashboard_button_settings")
                }
            }
            .refreshable {
                await viewModel.refresh(forceIP: true)
            }
            .task {
                viewModel.refreshAvailableNetworks()
                await viewModel.refresh(forceIP: true)
                viewModel.startAutoRefresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .networkProfilesDidChange)) { _ in
                viewModel.refreshAvailableNetworks()
            }
            .onDisappear {
                viewModel.stopAutoRefresh()
            }
            .accessibilityIdentifier("screen_dashboard")
        }
    }
}

// MARK: - HUD & Header

struct ConnectionStatusHeader: View {
    let viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: viewModel.isConnected ? .online : .offline, size: 8, animated: viewModel.isConnected)
            Text(viewModel.isConnected ? "MONITORING" : "OFFLINE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityIdentifier("dashboard_header_connectionStatus")
    }
}

struct OfflineBanner: View {
    let lastScanDate: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Offline — showing cached data")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.warning)

                if let date = lastScanDate {
                    Text("Updated \(date, style: .relative) ago")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemYellow).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                .stroke(Theme.Colors.warning.opacity(0.3), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard_banner_offline")
    }
}

struct TacticalHUDHeader: View {
    let viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: wifiIconName)
                                    .foregroundStyle(Theme.Colors.accent)
                                    .symbolEffect(.variableColor.reversing, isActive: viewModel.isScanning)
                                Text(viewModel.gateway?.ipAddress ?? "Scanning…")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.white, .white.opacity(0.8)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                            
                            HStack(spacing: 6) {
                                Text(viewModel.activeNetwork?.displayName ?? viewModel.currentWiFi?.ssid ?? "Unknown Network")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                if let channel = viewModel.currentWiFi?.channel {
                                    Text("•")
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                    Text("CH \(channel)")
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Theme.Colors.accent.opacity(0.1))
                                        .foregroundStyle(Theme.Colors.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            if let signal = viewModel.currentWiFi?.signalStrength {
                                // WiFi connected — show signal strength as hero
                                Text("\(signal)%")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [signalColor(signal), .white.opacity(0.8)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                if let latency = viewModel.gateway?.latency {
                                    Text("\(latency, specifier: "%.0f") ms")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            } else if let latency = viewModel.gateway?.latency {
                                // No WiFi info — show latency as hero
                                Text("\(latency, specifier: "%.0f") ms")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Theme.Colors.latencyColor(ms: latency), .white.opacity(0.8)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            } else {
                                Text("—")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("dashboard_header_network")
    }

    func signalColor(_ strength: Int) -> Color {
        if strength > 70 { return Theme.Colors.success }
        if strength > 40 { return Theme.Colors.warning }
        return Theme.Colors.error
    }

    var wifiIconName: String {
        guard let dbm = viewModel.currentWiFi?.signalDBm else { return "wifi" }
        if dbm > -50 { return "wifi" }
        if dbm > -60 { return "wifi" }
        if dbm > -70 { return "wifi" }
        return "wifi"
    }
}

// MARK: - Instruments

struct RefinedNetworkHealthCard: View {
    let viewModel: DashboardViewModel

    var healthScore: Int {
        if !viewModel.isConnected { return 0 }
        var score = 100
        if let latency = viewModel.gateway?.latency {
            if latency > 100 { score -= 50 }
            else if latency > 50 { score -= 30 }
            else if latency > 20 { score -= 10 }
        } else {
            score -= 30
        }
        if let signal = viewModel.currentWiFi?.signalStrength {
            if signal < 30 { score -= 30 }
            else if signal < 50 { score -= 20 }
            else if signal < 70 { score -= 10 }
        }
        let history = viewModel.latencyHistory
        if history.count >= 3 {
            let avg = history.reduce(0, +) / Double(history.count)
            let variance = history.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(history.count)
            let stddev = variance.squareRoot()
            if stddev > 20 { score -= 20 }
            else if stddev > 10 { score -= 10 }
        }
        return max(0, min(100, score))
    }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {

                // ── Header row ──────────────────────────────────────────
                HStack {
                    Text("NETWORK HEALTH")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(1.5)
                    Spacer()
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Theme.Colors.success)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.success.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                // ── Score + status ───────────────────────────────────────
                HStack(spacing: 16) {
                    // Compact score circle
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.05), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: CGFloat(healthScore) / 100.0)
                            .stroke(
                                LinearGradient(
                                    colors: [Theme.Colors.success, .cyan, Theme.Colors.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .shadow(color: .cyan.opacity(0.3), radius: 4)
                        VStack(spacing: -2) {
                            Text("\(healthScore)")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text("SCORE")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .tracking(1)
                        }
                    }
                    .frame(width: 64, height: 64)

                    // Status + key metrics
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(healthScore > 70 ? Theme.Colors.success : Theme.Colors.warning)
                                .frame(width: 6, height: 6)
                            Text(healthStatusTitle)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(healthDetailText)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineSpacing(1)
                    }
                }

                Divider().background(Color.white.opacity(0.06))

                // ── Connectivity rows ────────────────────────────────────
                VStack(spacing: 9) {
                    CompactConnRow(label: "ISP",       value: viewModel.ispInfo?.ispName ?? "Detecting…", icon: "antenna.radiowaves.left.and.right")
                    CompactConnRow(label: "DNS",       value: viewModel.systemDNS,                        icon: "magnifyingglass")
                    CompactConnRow(label: "Public IP", value: viewModel.ispInfo?.publicIP ?? "---.---.---.---", icon: "network")
                }

                // ── Anchor pills ─────────────────────────────────────────
                HStack(spacing: 8) {
                    AnchorPill(label: "Google",     latency: viewModel.anchorLatencies["Google"])
                    AnchorPill(label: "Cloudflare", latency: viewModel.anchorLatencies["Cloudflare"])
                    AnchorPill(label: "AWS",        latency: viewModel.anchorLatencies["AWS"])
                }
            }
        }
        .accessibilityIdentifier("dashboard_card_healthScore")
    }

    private var healthStatusTitle: String {
        if !viewModel.isConnected { return "Network Offline" }
        return healthScore > 80 ? "Optimal" : "Degraded"
    }

    private var healthDetailText: String {
        if !viewModel.isConnected { return "Check your local connection" }
        var parts: [String] = []
        parts.append("\(viewModel.deviceCount) devices")
        if let latency = viewModel.gateway?.latency { parts.append("GW \(Int(latency))ms") }
        if let signal = viewModel.currentWiFi?.signalStrength { parts.append("Signal \(signal)%") }
        return parts.joined(separator: " · ")
    }
}

private struct CompactConnRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 16)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

struct SignalEQView: View {
    let viewModel: DashboardViewModel
    
    var eqData: [Double] {
        let history = viewModel.latencyHistory
        guard !history.isEmpty else {
            // No data yet — show flat baseline
            return Array(repeating: 4.0, count: 40)
        }
        // Pad or trim to 40 bars, newest on right
        let reversed = Array(history.reversed())
        if reversed.count >= 40 {
            return Array(reversed.suffix(40))
        }
        let padding = Array(repeating: reversed.first ?? 4.0, count: 40 - reversed.count)
        return padding + reversed
    }
    
    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("STABILITY SPECTRUM (JITTER)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(1.5)
                    Spacer()
                }
                
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<eqData.count, id: \.self) { i in
                        let val = eqData[i]
                        let maxVal = eqData.max() ?? 100
                        let height = CGFloat((val / maxVal) * 32)
                        
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.Colors.latencyColor(ms: val), Theme.Colors.latencyColor(ms: val).opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(2, height))
                    }
                }
                .frame(height: 32)
            }
        }
    }
}

// MARK: - Pro Panels

struct AnchorPill: View {
    let label: String
    let latency: Double?
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(latency != nil ? Theme.Colors.success : Theme.Colors.textTertiary)
                .frame(width: 4, height: 4)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(Theme.Colors.textSecondary)
            if let ms = latency {
                Text("\(Int(ms))ms")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Text("—")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.Colors.crystalBase)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

// MARK: - Devices

struct LocalDevicesCard: View {
    @Bindable var viewModel: DashboardViewModel
    let selectedNetwork: NetworkProfile?

    var body: some View {
        NavigationLink(
            destination: DeviceListView(
                discoveredDevices: viewModel.discoveredDevices,
                networkProfile: selectedNetwork
            )
        ) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("ACTIVE DEVICES")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .tracking(1.5)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("\(viewModel.deviceCount) total")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.Colors.accent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(viewModel.discoveredDevices.prefix(5)) { device in
                            DeviceRow(device: device)
                            if device.id != viewModel.discoveredDevices.prefix(5).last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.05))
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    if viewModel.discoveredDevices.isEmpty {
                        Text("SEARCHING FOR HARDWARE...")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("dashboard_card_localDevices")
    }
}

struct DeviceRow: View {
    let device: DiscoveredDevice
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.Colors.crystalBase)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                
                Image(systemName: device.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(device.ipAddress)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(0.3)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.Colors.success)
                    .frame(width: 6, height: 6)
                Text(device.latencyText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.success)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Speed Test Quick Card

struct SpeedTestQuickCard: View {
    @Query(sort: \SpeedTestResult.timestamp, order: .reverse) private var history: [SpeedTestResult]

    private var lastResult: SpeedTestResult? { history.first }

    var body: some View {
        NavigationLink(destination: SpeedTestToolView()) {
            GlassCard(padding: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.Colors.accent.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "speedometer")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Speed Test")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)

                        if let result = lastResult {
                            Text(String(format: "Last: %.0f Mbps ↓ • %.0f Mbps ↑", result.downloadSpeed, result.uploadSpeed))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        } else {
                            Text("Tap to measure your connection speed")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("Run Now")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.Colors.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("dashboard_card_speedTest")
    }
}

// MARK: - Footer

struct LiveEventTicker: View {
    private var recentEvents: [ToolActivityItem] {
        Array(ToolActivityLog.shared.entries.prefix(3))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "terminal")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("LIVE EVENTS")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .tracking(1.5)
                    Spacer()
                    Circle().fill(recentEvents.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.success).frame(width: 4, height: 4)
                }

                if recentEvents.isEmpty {
                    Text("NO EVENTS YET")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(recentEvents) { event in
                            EventRow(
                                time: Self.timeFormatter.string(from: event.timestamp),
                                text: "\(event.tool): \(event.result)"
                            )
                        }
                    }
                }
            }
        }
    }
}

struct EventRow: View {
    let time: String
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Text(time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }
}

extension DiscoveredDevice {
    var iconName: String {
        let name = self.displayName.lowercased()
        if name.contains("iphone") { return "iphone" }
        if name.contains("macbook") || name.contains("mac") { return "laptopcomputer" }
        if name.contains("ipad") { return "ipad" }
        if name.contains("tv") { return "appletv" }
        if name.contains("homepod") { return "homepod.fill" }
        if name.contains("printer") || name.contains("jet") { return "printer" }
        return "desktopcomputer"
    }
}
