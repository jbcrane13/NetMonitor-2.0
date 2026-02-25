import SwiftUI
import NetMonitorCore
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self) private var session: MonitoringSession?
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?
    
    @AppStorage("netmonitor.appearance.compactMode") private var compactMode = false
    
    @Query private var targets: [NetworkTarget]
    @State private var graphMetric: GraphMetric = .latency
    
    enum GraphMetric: String, CaseIterable, Identifiable {
        case latency = "LATENCY"
        case signal = "SIGNAL"
        case loss = "LOSS"
        var id: String { self.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Full-Width Deep History Graph
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NETWORK TELEMETRY")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.secondary)
                                .tracking(1.5)
                            Text("Real-time persistent monitoring")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        
                        Spacer()
                        
                        Picker("", selection: $graphMetric) {
                            ForEach(GraphMetric.allCases) { metric in
                                Text(metric.rawValue).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                    }
                    
                    DeepHistoryGraph(metric: graphMetric, session: session)
                        .frame(height: 180)
                        .padding(20)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.8)
                                
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(MacTheme.Colors.crystalBase)

                                // Crystal Shine
                                LinearGradient(
                                    colors: [.white.opacity(0.08), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.2), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MacTheme.Colors.deckBorder, lineWidth: 0.5))
                }
                .padding(.horizontal)

                // 2. The Instrument Quad (4-Column Widgets)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    WiFiWidget()
                    GatewayWidget(session: session)
                    SpeedtestWidget()
                    PublicIPWidget(profileManager: profileManager)
                }
                .padding(.horizontal)

                // 3. Target Monitoring Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("TARGET MONITORING")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.secondary)
                            .tracking(1.5)
                        
                        Spacer()

                        if let session = session {
                            Button(action: {
                                if session.isMonitoring {
                                    session.stopMonitoring()
                                } else {
                                    session.startMonitoring()
                                }
                            }) {
                                Label(
                                    session.isMonitoring ? "STOP" : "START",
                                    systemImage: session.isMonitoring ? "stop.fill" : "play.fill"
                                )
                                .font(.system(size: 11, weight: .black))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(session.isMonitoring ? .red : .green)
                            .controlSize(.small)
                        }
                    }
                    
                    if targets.isEmpty {
                        NoTargetsView(onAdd: {})
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                            ForEach(targets) { target in
                                TargetStatusCard(
                                    target: target,
                                    measurement: session?.latestMeasurement(for: target.id)
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 24)
        }
        .background(
            ZStack {
                Color(hex: "020202")
                RadialGradient(
                    colors: [Color(hex: "0F172A").opacity(0.4), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 1000
                )
            }
        )
        .navigationTitle("Dashboard")
        .task {
            // Auto-seed and start if needed
            await seedDefaultTargetsIfNeeded()
            if let session, !session.isMonitoring {
                session.startMonitoring()
            }
        }
    }
    
    private func seedDefaultTargetsIfNeeded() async {
        if targets.isEmpty {
            // Seed Gateway and a couple of global targets
            let gateway = NetworkTarget(name: "Local Gateway", host: "192.168.1.1", targetProtocol: .icmp)
            let google = NetworkTarget(name: "Google DNS", host: "8.8.8.8", targetProtocol: .icmp)
            let cloudflare = NetworkTarget(name: "Cloudflare", host: "1.1.1.1", targetProtocol: .icmp)
            
            modelContext.insert(gateway)
            modelContext.insert(google)
            modelContext.insert(cloudflare)
            try? modelContext.save()
        }
    }
}

// MARK: - Sub-components

struct DeepHistoryGraph: View {
    let metric: DashboardView.GraphMetric
    let session: MonitoringSession?
    
    // Simulate history for visualization
    var historyData: [Double] {
        switch metric {
        case .latency: return (0..<60).map { _ in Double.random(in: 15...25) }
        case .signal: return (0..<60).map { _ in Double.random(in: -65...(-45)) }
        case .loss: return (0..<60).map { i in i % 20 == 0 ? 1.0 : 0.0 }
        }
    }
    
    var body: some View {
        VStack {
            HistorySparkline(
                data: historyData,
                color: metric == .latency ? .cyan : (metric == .signal ? .green : .red),
                lineWidth: 2,
                showPulse: true
            )
        }
    }
}

struct WiFiWidget: View {
    var body: some View {
        InstrumentWidget(title: "WIFI ENVIRONMENT", icon: "wifi") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom) {
                    Text("-42")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("dBm")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("SSID: Home_WiFi_6")
                        .font(.system(size: 11, weight: .medium))
                    Text("CHANNEL: 149 (5GHz)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct GatewayWidget: View {
    let session: MonitoringSession?
    var body: some View {
        InstrumentWidget(title: "GATEWAY STATUS", icon: "server.rack") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom) {
                    Text("2.4")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("ms")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("IP: 192.168.1.1")
                        .font(.system(size: 11, design: .monospaced))
                    Text("REACHABLE")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

struct SpeedtestWidget: View {
    @State private var isRunning = false
    var body: some View {
        InstrumentWidget(title: "SPEED TEST", icon: "bolt.fill") {
            VStack(alignment: .leading, spacing: 8) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    HStack(alignment: .bottom) {
                        Text("840")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("Mbps")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }
                    
                    Button(action: { isRunning = true; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isRunning = false } }) {
                        Text("RUN TEST")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PublicIPWidget: View {
    let profileManager: NetworkProfileManager?
    var body: some View {
        InstrumentWidget(title: "PUBLIC ACCESS", icon: "globe") {
            VStack(alignment: .leading, spacing: 8) {
                Text("74.125.22.101")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("ISP: Starlink")
                        .font(.system(size: 11, weight: .medium))
                    Text("LOCATION: Chicago, US")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct InstrumentWidget<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.cyan)
                Text(title)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
            
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .opacity(0.8)
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(MacTheme.Colors.crystalBase)

                // Crystal Shine
                LinearGradient(
                    colors: [.white.opacity(0.08), .clear, .white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        )
        .overlay(
            // Rim Light
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MacTheme.Colors.deckBorder, lineWidth: 0.5))
    }
}

struct NoTargetsView: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("NO TARGETS")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.secondary)
            Button("ADD FIRST TARGET", action: onAdd)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(MacTheme.Colors.deckBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TargetStatusCard: View {
    let target: NetworkTarget
    let measurement: TargetMeasurement?

    @State private var isHovering = false
    @State private var sweepOffset: CGFloat = -1.0

    // Simulate history based on latest measurement
    var simulatedHistory: [Double] {
        let base = measurement?.latency ?? 20.0
        return (0..<20).map { _ in max(1, base + Double.random(in: -5...5)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: target.targetProtocol.iconName)
                    .foregroundStyle(isHovering ? .white : .secondary)
                    .font(.system(size: 10, weight: .bold))

                Text(target.name.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.0)

                Spacer()

                // Status Indicator with Pulse
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.8), radius: isHovering ? 6 : 3, x: 0, y: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MacTheme.Colors.deckConsole)

            Divider()
                .background(MacTheme.Colors.deckBorder)

            VStack(alignment: .leading, spacing: 8) {
                // Host
                Text(target.host)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                // Sparkline (Recessed)
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(MacTheme.Colors.deckRecessed)
                    
                    HistorySparkline(data: simulatedHistory, color: statusColor, lineWidth: 1.5, showPulse: true)
                        .padding(4)
                }
                .frame(height: 34)

                // Metrics
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LATENCY")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)

                        if let latency = measurement?.latency {
                            Text(String(format: "%.1fms", latency))
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(MacTheme.Colors.latencyColor(ms: latency))
                        } else {
                            Text("—")
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SIGNAL")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)

                        Text(measurement?.isReachable ?? false ? "NOMINAL" : "LOST")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(measurement?.isReachable ?? false ? .green : .red)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 10)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .opacity(0.8)
                
                RoundedRectangle(cornerRadius: 10)
                    .fill(MacTheme.Colors.crystalBase)

                // Crystal Shine
                LinearGradient(
                    colors: [.white.opacity(0.08), .clear, .white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        )
        .overlay(
            // Rim Light
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.2), .white.opacity(0.05), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovering ? .white.opacity(0.3) : MacTheme.Colors.deckBorder, lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                sweepOffset = 1.5
            }
        }
    }

    private var statusColor: Color {
        guard let measurement = measurement else {
            return .gray
        }
        return measurement.isReachable ? .green : .red
    }
}
