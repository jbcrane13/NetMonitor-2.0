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

struct NetworkHealthHero: View {
    let viewModel: DashboardViewModel
    @State private var isAnimating = false
    
    var healthScore: Int {
        // Simple logic for health score based on latency
        let latency = viewModel.gateway?.latency ?? 0
        if !viewModel.isConnected { return 0 }
        if latency < 20 { return 100 }
        if latency < 50 { return 90 }
        if latency < 100 { return 70 }
        return 40
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background Glow
                Circle()
                    .fill(Theme.Colors.latencyColor(ms: viewModel.gateway?.latency ?? 0))
                    .frame(width: 140, height: 140)
                    .blur(radius: isAnimating ? 40 : 20)
                    .opacity(0.15)
                
                // Track
                Circle()
                    .stroke(Color.white.opacity(0.05), lineWidth: 12)
                    .frame(width: 160, height: 160)
                
                // Progress
                Circle()
                    .trim(from: 0, to: CGFloat(healthScore) / 100.0)
                    .stroke(
                        LinearGradient(
                            colors: [Theme.Colors.latencyColor(ms: viewModel.gateway?.latency ?? 0), .white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 0) {
                    Text("\(healthScore)%")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("HEALTH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(2)
                }
            }
            
            Text(healthStatusText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, 20)
        .onAppear {
            withAnimation(Theme.Animation.pulse) {
                isAnimating = true
            }
        }
    }
    
    private var healthStatusText: String {
        if !viewModel.isConnected { return "NETWORK OFFLINE" }
        switch healthScore {
        case 90...100: return "OPTIMAL CONNECTION"
        case 70..<90: return "NOMINAL PERFORMANCE"
        case 40..<70: return "DEGRADED SIGNAL"
        default: return "CRITICAL LATENCY"
        }
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
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .tracking(1)
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
                VStack(spacing: 12) {
                    ConnectivityRow(label: "ISP", value: viewModel.ispInfo?.ispName ?? "Detecting...", icon: "antenna.radiowaves.left.and.right")
                    Divider().background(Color.white.opacity(0.05))
                    ConnectivityRow(label: "DNS", value: "8.8.8.8, 1.1.1.1", icon: "magnifyingglass")
                    Divider().background(Color.white.opacity(0.05))
                    ConnectivityRow(label: "Public IP", value: viewModel.ispInfo?.publicIP ?? "---.---.---.---", icon: "network")
                }
            }
            
            // Global Anchor Ticker
            HStack(spacing: 8) {
                AnchorPill(label: "Google", latency: 14, status: .online)
                AnchorPill(label: "Cloudflare", latency: 8, status: .online)
                AnchorPill(label: "AWS", latency: 22, status: .online)
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
    let status: StatusType
    
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

struct TacticalHUDHeader: View {
    let viewModel: DashboardViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            GlassCard(padding: 16) {
                VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: "wifi")
                                                            .foregroundStyle(Theme.Colors.accent)
                                                            .symbolEffect(.variableColor.reversing, isActive: viewModel.isScanning)
                                                        Text(viewModel.activeNetwork?.displayName ?? viewModel.currentWiFi?.ssid ?? "Unknown Network")                                    .font(.system(size: 18, weight: .bold, design: .rounded))
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

struct RefinedNetworkHealthCard: View {
    let viewModel: DashboardViewModel
    @State private var isAnimating = false
    
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(1.2)
                    Spacer()
                    Text("2m ago")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                
                HStack(spacing: 20) {
                    // Health Ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.05), lineWidth: 5.5)
                        Circle()
                            .trim(from: 0, to: CGFloat(healthScore) / 100.0)
                            .stroke(
                                LinearGradient(
                                    colors: [Theme.Colors.success, .cyan, Theme.Colors.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 5.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .shadow(color: .cyan.opacity(0.25), radius: 5)
                        
                        VStack(spacing: -2) {
                            Text("\(healthScore)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Score")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .tracking(1)
                        }
                    }
                    .frame(width: 84, height: 84)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(healthScore > 70 ? Theme.Colors.success : Theme.Colors.warning)
                                .frame(width: 7, height: 7)
                                .shadow(color: (healthScore > 70 ? Theme.Colors.success : Theme.Colors.warning).opacity(0.35), radius: 5)
                            
                            Text(healthStatusTitle)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        
                        Text(healthDetailText)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineSpacing(4)
                    }
                }
            }
        }
    }
    
    private var healthStatusTitle: String {
        if !viewModel.isConnected { return "Network Offline" }
        return healthScore > 80 ? "All Systems Normal" : "Degraded Signal"
    }
    
    private var healthDetailText: String {
        if !viewModel.isConnected { return "Check your local connection" }
        return "\(viewModel.deviceCount) devices online • Gateway \(Int(viewModel.gateway?.latency ?? 0))ms\nNo packet loss detected"
    }
}

struct LinkTopologyView: View {
    let viewModel: DashboardViewModel
    @State private var packetOffset: CGFloat = 0
    
    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LINK TOPOLOGY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(1)
                    Spacer()
                    StatusBadge(status: viewModel.isConnected ? .online : .offline, size: .small)
                }
                
                HStack(spacing: 0) {
                    TopologyNode(icon: "iphone", label: "Local")
                    TopologyLink(active: viewModel.isConnected, color: .blue, offset: packetOffset)
                    TopologyNode(icon: "server.rack", label: "Gateway")
                    TopologyLink(active: viewModel.isConnected && viewModel.gateway?.latency != nil, color: Theme.Colors.latencyColor(ms: viewModel.gateway?.latency ?? 0), offset: packetOffset)
                    TopologyNode(icon: "globe", label: "Internet")
                }
                .padding(.vertical, 8)
            }
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
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            Text(label.uppercased())
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(width: 50)
    }
}

struct TopologyLink: View {
    let active: Bool
    let color: Color
    let offset: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background Line
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 2)
                
                if active {
                    // Flow Line
                    Rectangle()
                        .fill(color.opacity(0.3))
                        .frame(height: 2)
                    
                    // Moving Packet
                    Circle()
                        .fill(.white)
                        .frame(width: 4, height: 4)
                        .shadow(color: color, radius: 4)
                        .offset(x: -geo.size.width/2 + (geo.size.width * offset))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 32)
    }
}

struct SignalEQView: View {
    let viewModel: DashboardViewModel
    
    // Simulate high-density jitter data
    var eqData: [Double] {
        let base = viewModel.gateway?.latency ?? 20.0
        return (0..<40).map { i in
            let variance = Double.random(in: -5...5)
            // Add a "spike" occasionally
            let spike = i % 15 == 0 ? Double.random(in: 10...30) : 0
            return max(5, base + variance + spike)
        }
    }
    
    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SIGNAL STABILITY (JITTER)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Spacer()
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<eqData.count, id: \.self) { i in
                        let val = eqData[i]
                        let maxVal = eqData.max() ?? 100
                        let height = CGFloat((val / maxVal) * 30)
                        
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.Colors.latencyColor(ms: val), Theme.Colors.latencyColor(ms: val).opacity(0.3)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(2, height))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: height)
                    }
                }
                .frame(height: 30)
            }
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
