// swiftlint:disable file_length
import SwiftUI
import NetMonitorCore
import NetworkScanKit
import SwiftData

struct DashboardView: View {
    @State private var viewModel: DashboardViewModel
    @State private var healthViewModel = NetworkHealthScoreViewModel()
    @State private var lastHealthRefresh: Date?
    // periphery:ignore
    @State private var isAddNetworkSheetPresented = false

    init(env: AppEnvironment) {
        _viewModel = State(initialValue: DashboardViewModel(
            networkMonitor: env.networkMonitor,
            wifiService: env.wifiInfo,
            publicIPService: env.publicIP,
            deviceDiscoveryService: env.deviceDiscovery,
            macConnectionService: env.macConnection
        ))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    dashboardContent(width: geo.size.width)
                        .padding(.horizontal, Theme.Layout.screenPadding)
                        .padding(.top, Theme.Layout.smallCornerRadius)
                        .padding(.bottom, Theme.Layout.sectionSpacing)
                }
                .appDestinations()
                .navigationDestination(for: DeviceListRoute.self) { _ in
                    DeviceListView(
                        discoveredDevices: viewModel.discoveredDevices,
                        networkProfile: viewModel.activeNetwork
                    )
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
                    refreshHealthIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: .networkProfilesDidChange)) { _ in
                    viewModel.refreshAvailableNetworks()
                }
                .onChange(of: viewModel.isRefreshing) { _, isRefreshing in
                    if !isRefreshing {
                        refreshHealthIfNeeded()
                    }
                }
                .onDisappear {
                    viewModel.stopAutoRefresh()
                }
                .accessibilityIdentifier("screen_dashboard")
            }
        }
    }

    /// Refreshes the health score at most once every 60 seconds, since each
    /// refresh pings 8.8.8.8 five times (`NetworkHealthScoreViewModel.refresh()`).
    private func refreshHealthIfNeeded() {
        let now = Date()
        if let last = lastHealthRefresh, now.timeIntervalSince(last) < 60 {
            return
        }
        lastHealthRefresh = now
        healthViewModel.refresh()
    }

    @ViewBuilder
    private func dashboardContent(width: CGFloat) -> some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            if !viewModel.isConnected {
                OfflineBanner(lastScanDate: viewModel.lastScanDate)
            }

            TacticalHUDHeader(viewModel: viewModel)

            if width > 900 {
                // Wide: 3-column grid for metric cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Theme.Layout.itemSpacing) {
                    RefinedNetworkHealthCard(viewModel: viewModel, healthViewModel: healthViewModel)
                    SignalEQView(viewModel: viewModel)
                    WANInfoCard(viewModel: viewModel)
                }
                AnchorLatencyCard(viewModel: viewModel)
            } else if width > 600 {
                // Regular: 2-column pairs
                HStack(spacing: Theme.Layout.itemSpacing) {
                    RefinedNetworkHealthCard(viewModel: viewModel, healthViewModel: healthViewModel)
                        .frame(maxWidth: .infinity)
                    SignalEQView(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: Theme.Layout.itemSpacing) {
                    WANInfoCard(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                    AnchorLatencyCard(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                }
            } else {
                // Compact: single column (iPhone default)
                RefinedNetworkHealthCard(viewModel: viewModel, healthViewModel: healthViewModel)
                SignalEQView(viewModel: viewModel)
                WANInfoCard(viewModel: viewModel)
                AnchorLatencyCard(viewModel: viewModel)
            }

            SpeedTestQuickCard()

            WiFiHeatmapQuickCard()

            LiveEventTicker()

            LocalDevicesCard(viewModel: viewModel)
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
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityIdentifier("dashboard_label_connectionStatus")
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
                        .font(.system(.caption2))
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
        .accessibilityIdentifier("dashboard_label_offline")
    }
}

struct TacticalHUDHeader: View {
    let viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            GlassCard(padding: 16, statusGlow: Theme.Colors.info) {
                VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: "wifi", variableValue: wifiSignalFraction)
                                    .foregroundStyle(Theme.Colors.accent)
                                    .symbolEffect(.variableColor.reversing, isActive: viewModel.isScanning)
                                Text(viewModel.gateway?.ipAddress ?? "Scanning…")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Theme.Colors.textStrong, Theme.Colors.textStrong.opacity(0.8)],
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
                                        .font(.system(.caption2, design: .monospaced, weight: .black))
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
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [signalColor(signal), Theme.Colors.textStrong.opacity(0.8)],
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
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Theme.Colors.latencyColor(ms: latency), Theme.Colors.textStrong.opacity(0.8)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            } else {
                                Text("—")
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("dashboard_label_network")
    }

    func signalColor(_ strength: Int) -> Color {
        Theme.Colors.color(for: NetworkHealthScore.signalSeverity(percent: strength))
    }

    var wifiSignalFraction: Double {
        guard let signal = viewModel.currentWiFi?.signalStrength else { return 1.0 }
        return min(max(Double(signal) / 100.0, 0.0), 1.0)
    }
}

// MARK: - Instruments

struct RefinedNetworkHealthCard: View {
    let viewModel: DashboardViewModel
    let healthViewModel: NetworkHealthScoreViewModel

    var body: some View {
        GlassCard(padding: 12, statusGlow: Theme.Colors.info) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("NETWORK HEALTH")
                        .font(.system(.caption2, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(2.0)
                    Spacer()
                    Text("LIVE")
                        .font(.system(.caption2, weight: .black))
                        .foregroundStyle(Theme.Colors.success)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.success.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Theme.Colors.divider, lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: CGFloat(healthViewModel.scoreValue) / 100.0)
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
                            Text("\(healthViewModel.scoreValue)")
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.Colors.textStrong)
                            Text(healthViewModel.gradeText)
                                .font(.system(.caption2, weight: .black))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .tracking(1)
                        }
                    }
                    .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(healthViewModel.scoreValue > 70 ? Theme.Colors.success : Theme.Colors.warning)
                                .frame(width: 6, height: 6)

                            Text(healthStatusTitle)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.Colors.textStrong)
                        }

                        Text(healthDetailText)
                            .font(.system(.caption2))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineSpacing(1)
                    }
                }
            }
        }
        .accessibilityIdentifier("dashboard_card_healthScore")
    }

    private var healthStatusTitle: String {
        if !viewModel.isConnected {
            return "Network Offline"
        }
        return healthViewModel.scoreValue > 80 ? "Optimal Performance" : "Degraded Signal"
    }

    private var healthDetailText: String {
        if !viewModel.isConnected {
            return "Check your local connection"
        }
        var parts: [String] = []
        parts.append("\(viewModel.deviceCount) devices active")
        if let latency = viewModel.gateway?.latency {
            parts.append("Gateway \(Int(latency))ms")
        }
        if let signal = viewModel.currentWiFi?.signalStrength {
            parts.append("Signal \(signal)%")
        }
        return parts.joined(separator: " • ")
    }
}

struct SignalEQView: View {
    let viewModel: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Bar height scales up on iPad to fill the taller card
    private var barMaxHeight: CGFloat {
        sizeClass == .regular ? 64 : 32
    }

    var eqData: [Double] {
        let history = viewModel.latencyHistory
        guard !history.isEmpty else {
            // No data yet — show animated placeholder bars
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

    var hasRealData: Bool {
        viewModel.latencyHistory.count >= 3
    }

    var body: some View {
        GlassCard(padding: 12, statusGlow: Theme.Colors.info) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("STABILITY SPECTRUM (JITTER)")
                        .font(.system(.caption2, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(2.0)
                    Spacer()
                    if !hasRealData {
                        Text("COLLECTING…")
                            .font(.system(.caption2, weight: .black))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                HStack(alignment: .bottom, spacing: 2) {
                    // Use minimum ceiling of 20ms so baseline 4ms bars render at ~6.4pt (visible)
                    // Scale up actual jitter values proportionally
                    let ceiling = max((eqData.max() ?? 20.0) * 1.5, 20.0)
                    ForEach(0..<eqData.count, id: \.self) { i in
                        let val = eqData[i]
                        let normalized = min(val / ceiling, 1.0)
                        let height = CGFloat(normalized * Double(barMaxHeight))

                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        barColor(for: val, hasData: hasRealData),
                                        barColor(for: val, hasData: hasRealData).opacity(0.4)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(3, height))
                    }
                }
                .frame(height: barMaxHeight)
            }
        }
    }

    private func barColor(for latency: Double, hasData: Bool) -> Color {
        if !hasData {
            // Placeholder bars: subtle amber/gold to indicate "warming up"
            return Theme.Colors.accent.opacity(0.6)
        }
        return Theme.Colors.latencyColor(ms: latency)
    }
}

// MARK: - Pro Panels

// MARK: - WAN Info Card
struct WANInfoCard: View {
    let viewModel: DashboardViewModel

    var body: some View {
        GlassCard(padding: 12, statusGlow: Theme.Colors.info) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WAN INFO")
                    .font(.system(.caption2, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(2.0)

                VStack(spacing: 0) {
                    ConnectivityRow(
                        label: "ISP",
                        value: viewModel.ispInfo?.ispName ?? "Detecting…",
                        icon: "antenna.radiowaves.left.and.right"
                    )
                    Divider().background(Theme.Colors.divider).padding(.vertical, 6)
                    ConnectivityRow(
                        label: "Public IP",
                        value: viewModel.ispInfo?.publicIP ?? "—",
                        icon: "network"
                    )
                    Divider().background(Theme.Colors.divider).padding(.vertical, 6)
                    ConnectivityRow(
                        label: "DNS",
                        value: viewModel.systemDNS,
                        icon: "magnifyingglass"
                    )
                }
            }
        }
        .accessibilityIdentifier("dashboard_card_wan")
    }
}

// MARK: - Anchor Latency Card
struct AnchorLatencyCard: View {
    let viewModel: DashboardViewModel

    private let anchors: [(label: String, key: String)] = [
        ("Google", "Google"),
        ("Cloudflare", "Cloudflare"),
        ("Apple", "Apple")
    ]

    var body: some View {
        GlassCard(padding: 12, statusGlow: Theme.Colors.info) {
            VStack(alignment: .leading, spacing: 10) {
                Text("INTERNET LATENCY")
                    .font(.system(.caption2, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(2.0)

                HStack(spacing: 0) {
                    ForEach(anchors, id: \.key) { anchor in
                        AnchorMetricColumn(
                            label: anchor.label,
                            latency: viewModel.anchorLatencies[anchor.key]
                        )
                        if anchor.key != anchors.last?.key {
                            Divider()
                                .background(Theme.Colors.divider)
                                .frame(height: 36)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("dashboard_card_anchorLatency")
    }
}

struct AnchorMetricColumn: View {
    let label: String
    let latency: Double?

    private var dotColor: Color {
        guard let ms = latency else { return Theme.Colors.textTertiary }
        return Theme.Colors.color(for: NetworkHealthScore.latencySeverity(ms: ms))
    }

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            if let ms = latency {
                Text("\(Int(ms))")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textStrong)
                Text("ms")
                    .font(.system(.caption2, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(0.5)
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text("ms")
                    .font(.system(.caption2, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(0.5)
            }
            Text(label.uppercased())
                .font(.system(.caption2, weight: .heavy))
                .foregroundStyle(Theme.Colors.textTertiary)
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ConnectivityRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 20)

            Text(label.uppercased())
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textStrong)
        }
    }
}

// MARK: - Devices

/// Value-based navigation route for the dashboard's local-devices card.
///
/// Commit c84fefd converted the device row's push (inside `DeviceListView`)
/// from `NavigationLink(destination:)` to `NavigationLink(value:
/// AppDestination.deviceDetail)`, but left this card's own push to
/// `DeviceListView` as a legacy `NavigationLink(destination:)`. That mix
/// meant the row's `path`-driven push had to be reconciled with the card's
/// older identity/`isActive`-driven push, and while `DashboardViewModel`
/// kept publishing (e.g. during an active scan), that reconciliation
/// stalled the device-detail push for several seconds (#318). Routing both
/// hops through `NavigationLink(value:)` puts them on the same mechanism
/// and removes the stall.
private struct DeviceListRoute: Hashable {}

struct LocalDevicesCard: View {
    @Bindable var viewModel: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Show all devices on iPad, cap at 5 on iPhone
    private var visibleDevices: [DiscoveredDevice] {
        if sizeClass == .regular {
            return Array(viewModel.discoveredDevices)
        }
        return Array(viewModel.discoveredDevices.prefix(5))
    }

    var body: some View {
        NavigationLink(value: DeviceListRoute()) {
            GlassCard(statusGlow: Theme.Colors.info) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("ACTIVE DEVICES")
                            .font(.system(.caption2, weight: .heavy))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .tracking(2.0)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("\(viewModel.deviceCount) total")
                                .font(.system(.caption2, weight: .bold))
                                .foregroundStyle(Theme.Colors.accent)
                            Image(systemName: "chevron.right")
                                .font(.system(.caption2, weight: .bold))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach(visibleDevices) { device in
                            DeviceRow(device: device)
                            if device.id != visibleDevices.last?.id {
                                Divider()
                                    .background(Theme.Colors.divider)
                                    .padding(.vertical, 4)
                            }
                        }
                    }

                    if viewModel.discoveredDevices.isEmpty {
                        HStack(spacing: 8) {
                            if viewModel.isScanning {
                                ProgressView(value: viewModel.scanProgress)
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                                Text("SCANNING • \(viewModel.scanPhase.rawValue.uppercased())")
                            } else if !viewModel.isConnected {
                                Image(systemName: "wifi.slash")
                                Text("CONNECT TO WI-FI TO SCAN")
                            } else if viewModel.lastScanDate != nil {
                                Image(systemName: "arrow.clockwise")
                                Text("NO DEVICES FOUND • SCAN AGAIN")
                            } else {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                Text("NO SCAN YET • RUN A DEVICE SCAN")
                            }
                        }
                        .font(.system(.caption2, design: .monospaced, weight: .black))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                        .accessibilityIdentifier("dashboard_devices_emptyState")
                    }
                }
            }
            .accessibilityIdentifier("dashboard_card_localDevices")
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxHeight: sizeClass == .regular ? .infinity : nil)
        .accessibilityIdentifier("dashboard_link_devices")
        .accessibilityValue("\(viewModel.deviceCount) devices")
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
                            .stroke(Theme.Colors.divider, lineWidth: 1)
                    )

                Image(systemName: device.iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.textStrong)
                Text(device.ipAddress)
                    .font(.system(.caption2, design: .monospaced))
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
    private static var latestResultDescriptor: FetchDescriptor<SpeedTestResult> {
        var descriptor = FetchDescriptor<SpeedTestResult>(
            sortBy: [SortDescriptor(\SpeedTestResult.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    @Query(Self.latestResultDescriptor) private var history: [SpeedTestResult]

    private var lastResult: SpeedTestResult? { history.first }

    var body: some View {
        NavigationLink(value: AppDestination.speedTest) {
            GlassCard(padding: 14, statusGlow: Theme.Colors.info) {
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
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        } else {
                            Text("Tap to measure your connection speed")
                                .font(.system(.caption2))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("Run Now")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.Colors.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption2, weight: .bold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .accessibilityIdentifier("dashboard_card_speedTest")
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("dashboard_link_speedTest")
    }
}

// MARK: - Wi-Fi Heatmap Quick Card

struct WiFiHeatmapQuickCard: View {
    private static let iconMesh = MeshGradient(
        width: 3,
        height: 3,
        points: [
            .init(0, 0), .init(0.5, 0), .init(1, 0),
            .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
            .init(0, 1), .init(0.5, 1), .init(1, 1)
        ],
        colors: [
            .cyan.opacity(0.35), .teal.opacity(0.25), .cyan.opacity(0.20),
            .teal.opacity(0.20), .cyan.opacity(0.30), .blue.opacity(0.20),
            .cyan.opacity(0.18), .teal.opacity(0.22), .blue.opacity(0.15)
        ]
    )

    var body: some View {
        NavigationLink(value: AppDestination.heatmapSurvey) {
            GlassCard(padding: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Self.iconMesh)
                            .frame(width: 40, height: 40)
                        Image(systemName: "wifi.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wi-Fi Heatmap")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("Map signal coverage across your space")
                            .font(.system(.caption2))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("Start")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.cyan)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption2, weight: .bold))
                            .foregroundStyle(.cyan)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cyan.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .accessibilityIdentifier("dashboard_card_wifiHeatmap")
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("dashboard_link_heatmap")
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
        GlassCard(padding: 12, statusGlow: Theme.Colors.info) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "terminal")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("LIVE EVENTS")
                        .font(.system(.caption2, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .tracking(2.0)
                    Spacer()
                    Circle().fill(recentEvents.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.success).frame(width: 4, height: 4)
                }

                if recentEvents.isEmpty {
                    Text("NO EVENTS YET")
                        .font(.system(.caption2, design: .monospaced, weight: .black))
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
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }
}

extension DiscoveredDevice {
    var iconName: String {
        let name = self.displayName.lowercased()
        if name.contains("iphone") {
            return "iphone"
        }
        if name.contains("macbook") || name.contains("mac") {
            return "laptopcomputer"
        }
        if name.contains("ipad") {
            return "ipad"
        }
        if name.contains("tv") {
            return "appletv"
        }
        if name.contains("homepod") {
            return "homepod.fill"
        }
        if name.contains("printer") || name.contains("jet") {
            return "printer"
        }
        return "desktopcomputer"
    }
}

// swiftlint:enable file_length
