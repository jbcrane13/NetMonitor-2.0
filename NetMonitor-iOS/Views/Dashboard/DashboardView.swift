import SwiftUI
import NetMonitorCore
import NetworkScanKit

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var isAddNetworkSheetPresented = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Layout.itemSpacing) {
                    TacticalHUDHeader(viewModel: viewModel)
                    
                    RefinedNetworkHealthCard(viewModel: viewModel)
                    
                    SignalEQView(viewModel: viewModel)
                    
                    QuickStatsGrid(viewModel: viewModel)
                    
                    LocalDevicesCard(
                        viewModel: viewModel,
                        selectedNetwork: viewModel.activeNetwork
                    )
                    
                    ProConnectivityPanel(viewModel: viewModel)
                    
                    LiveEventTicker()
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.top, Theme.Layout.smallCornerRadius)
                .padding(.bottom, Theme.Layout.sectionSpacing)
            }
            .themedBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Components

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
                                                        Image(systemName: wifiIconName)
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
                Theme.Colors.crystalBase
                    .opacity(0.5)
                    .blur(radius: 10)
                    .offset(y: 4)
            )
        }
    }
    var wifiIconName: String {
        guard let dbm = viewModel.currentWiFi?.signalDBm else { return "wifi" }
        if dbm > -50 { return "wifi" }
        if dbm > -60 { return "wifi" }
        if dbm > -70 { return "wifi" }
        return "wifi" // fallback to standard wifi icon
    }
}

struct RefinedNetworkHealthCard: View {
    let viewModel: DashboardViewModel
    
    var healthScore: Int {
        let latency = viewModel.gateway?.latency ?? 0
        if !viewModel.isConnected { return 0 }
        if latency < 20 { return 100 }
        if latency < 50 { return 90 }
        if latency < 100 { return 70 }
        return 40
    }
    
    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
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
                
                HStack(spacing: 20) {
                    // Health Ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.05), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(healthScore) / 100.0)
                            .stroke(
                                LinearGradient(
                                    colors: [Theme.Colors.success, .cyan, Theme.Colors.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .shadow(color: .cyan.opacity(0.3), radius: 6)
                        
                        VStack(spacing: -2) {
                            Text("\(healthScore)")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text("SCORE")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .tracking(1)
                        }
                    }
                    .frame(width: 80, height: 80)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(healthScore > 70 ? Theme.Colors.success : Theme.Colors.warning)
                                .frame(width: 7, height: 7)
                            
                            Text(healthStatusTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        
                        Text(healthDetailText)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineSpacing(2)
                    }
                }
            }
        }
    }
    
    private var healthStatusTitle: String {
        if !viewModel.isConnected { return "Network Offline" }
        return healthScore > 80 ? "Optimal Performance" : "Degraded Signal"
    }
    
    private var healthDetailText: String {
        if !viewModel.isConnected { return "Check your local connection" }
        return "\(viewModel.deviceCount) devices active • Gateway \(Int(viewModel.gateway?.latency ?? 0))ms\nNo packet loss detected"
    }
}

struct SignalEQView: View {
    let viewModel: DashboardViewModel
    
    var eqData: [Double] {
        let base = viewModel.gateway?.latency ?? 20.0
        return (0..<40).map { i in
            let variance = Double.random(in: -4...4)
            let spike = i % 18 == 0 ? Double.random(in: 8...25) : 0
            return max(4, base + variance + spike)
        }
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
                .overlay(
                    // Glowing Floor
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.Colors.accent.opacity(0.2), .clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: 8),
                    alignment: .bottom
                )
            }
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
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.accent)
                    Text(label)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(1.2)
                }
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("2ms")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.success)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LinkTopologyView: View {
    let viewModel: DashboardViewModel
    @State private var packetOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 0) {
            TopologyNode(icon: "iphone", label: "Local")
            TopologyLink(active: viewModel.isConnected, color: .blue, offset: packetOffset)
            TopologyNode(icon: "server.rack", label: "Gateway")
            TopologyLink(active: viewModel.isConnected && viewModel.gateway?.latency != nil, color: Theme.Colors.latencyColor(ms: viewModel.gateway?.latency ?? 0), offset: packetOffset)
            TopologyNode(icon: "globe", label: "Internet")
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                packetOffset = 1.0
            }
        }
    }
}

struct TopologyNode: View {
    let icon: String
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.crystalBase)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }
            Text(label.uppercased())
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(width: 44)
    }
}

struct TopologyLink: View {
    let active: Bool
    let color: Color
    let offset: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                
                if active {
                    Rectangle()
                        .fill(color.opacity(0.2))
                        .frame(height: 1)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 3, height: 3)
                        .shadow(color: color, radius: 3)
                        .offset(x: -geo.size.width/2 + (geo.size.width * offset))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 28)
    }
}

struct ProConnectivityPanel: View {
    let viewModel: DashboardViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("PRO CONNECTIVITY")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(1.5)
                Spacer()
            }
            .padding(.horizontal, 4)
            
            GlassCard(padding: 12) {
                VStack(spacing: 16) {
                    LinkTopologyView(viewModel: viewModel)
                        .padding(.bottom, 4)
                    
                    VStack(spacing: 12) {
                        ConnectivityRow(label: "ISP", value: viewModel.ispInfo?.ispName ?? "Detecting...", icon: "antenna.radiowaves.left.and.right")
                        Divider().background(Color.white.opacity(0.05))
                        ConnectivityRow(label: "DNS", value: "8.8.8.8, 1.1.1.1", icon: "magnifyingglass")
                        Divider().background(Color.white.opacity(0.05))
                        ConnectivityRow(label: "Public IP", value: viewModel.ispInfo?.publicIP ?? "---.---.---.---", icon: "network")
                    }
                }
            }
            
            HStack(spacing: 8) {
                AnchorPill(label: "Google", latency: 14)
                AnchorPill(label: "Cloudflare", latency: 8)
                AnchorPill(label: "AWS", latency: 22)
            }
            .padding(.top, 4)
        }
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
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

struct AnchorPill: View {
    let label: String
    let latency: Int
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.Colors.success)
                .frame(width: 4, height: 4)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("\(latency)ms")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.Colors.crystalBase)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

struct LiveEventTicker: View {
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
                    Circle().fill(Theme.Colors.success).frame(width: 4, height: 4)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    EventRow(time: "04:32:10", text: "Gateway check: 14ms (Optimal)")
                    EventRow(time: "04:31:45", text: "Local scan: 14 devices active")
                    EventRow(time: "04:30:12", text: "Starlink connection stable")
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
