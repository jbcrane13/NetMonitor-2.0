import SwiftUI
import NetMonitorCore

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var isAddNetworkSheetPresented = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Layout.itemSpacing) {
                    TacticalHUDHeader(viewModel: viewModel)
                    
                    QuickStatsGrid(viewModel: viewModel)
                    
                    if let _ = viewModel.gateway {
                        GatewaySparklineCard(viewModel: viewModel)
                    }

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
            .navigationBarTitleDisplayMode(.inline) // Changed to inline for HUD feel
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        }
        .accessibilityIdentifier("screen_dashboard")
    }
}

struct ConnectionStatusHeader: View {
    let viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: viewModel.isConnected ? .online : .offline, size: 8, animated: viewModel.isConnected)
            Text(viewModel.isConnected ? "MONITORING" : "OFFLINE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
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
                                Image(systemName: viewModel.connectionType.iconName)
                                    .foregroundStyle(Theme.Colors.accent)
                                    .symbolEffect(.variableColor.reversing, isActive: viewModel.isScanning)
                                Text(viewModel.activeNetwork?.displayName ?? viewModel.currentWiFi?.ssid ?? "Unknown Network")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.white, .white.opacity(0.8)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                            
                            Text(viewModel.ispInfo?.ispName ?? "Detecting ISP...")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(viewModel.ispInfo?.publicIP ?? "---.---.---.---")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(viewModel.gateway?.latency ?? 0, specifier: "%.0f") ms")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Theme.Colors.latencyColor(ms: viewModel.gateway?.latency ?? 0), .white.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            if let dbm = viewModel.currentWiFi?.signalDBm {
                                Text("\(dbm) dBm")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                Theme.Colors.obsidianCardBase
                    .opacity(0.5)
                    .blur(radius: 10)
                    .offset(y: 4)
            )
        }
    }
}

struct QuickStatsGrid: View {
    let viewModel: DashboardViewModel
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Layout.itemSpacing) {
            StatWidget(label: "Gateway", value: viewModel.gateway?.ipAddress ?? "---", icon: "server.rack")
            StatWidget(label: "Devices", value: "\(viewModel.deviceCount)", icon: "desktopcomputer")
            StatWidget(label: "Session", value: viewModel.sessionDuration, icon: "clock")
            StatWidget(label: "WiFi Ch.", value: viewModel.currentWiFi?.channel.map { "\($0)" } ?? "---", icon: "wifi")
        }
    }
}

struct StatWidget: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .textCase(.uppercase)
                }
                Text(value)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct GatewaySparklineCard: View {
    let viewModel: DashboardViewModel
    
    // Simulate some history data for the sparkline if real history isn't available in viewModel
    // In a real app, viewModel should provide an array of past latencies.
    var simulatedHistory: [Double] {
        let base = viewModel.gateway?.latency ?? 20.0
        return (0..<20).map { _ in max(1, base + Double.random(in: -5...5)) }
    }
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LIVE LATENCY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    if let latency = viewModel.gateway?.latency {
                        Text("\(latency, specifier: "%.0f") ms")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.Colors.latencyColor(ms: latency))
                    }
                }
                
                HistorySparkline(data: simulatedHistory, color: Theme.Colors.accent, lineWidth: 2, showPulse: true)
                    .frame(height: 40)
            }
        }
    }
}

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
                VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Critical Devices")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("\(viewModel.deviceCount) total")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }

                    // Just show top 3 devices
                    VStack(spacing: 8) {
                        ForEach(viewModel.discoveredDevices.prefix(3)) { device in
                            HStack {
                                Circle()
                                    .fill(Theme.Colors.success)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: Theme.Colors.success.opacity(0.8), radius: 4, x: 0, y: 0)
                                Text(device.displayName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(device.ipAddress)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    
                    if viewModel.discoveredDevices.isEmpty {
                        Text("No devices found or scan pending.")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    if viewModel.isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            viewModel.refreshAvailableNetworks()
        }
        .accessibilityIdentifier("dashboard_card_localDevices")
    }
}
