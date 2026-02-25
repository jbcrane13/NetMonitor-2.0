import SwiftUI
import NetMonitorCore
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self) private var session: MonitoringSession?
    @Environment(\.compactMode) private var compactMode

    @Query(sort: \NetworkTarget.name) private var targets: [NetworkTarget]

    var body: some View {
        ScrollView {
            VStack(spacing: compactMode ? 16 : 24) {
                // Unified Instrument Panel
                InstrumentPanel(session: session)
                    .padding(.horizontal)

                // Header / Monitoring Controls
                HStack {
                    Text("TARGET MONITORING")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                    
                    Spacer()

                    // Start/Stop Button
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
                .padding(.horizontal)

                // Error Message Display
                if let session = session, let errorMessage = session.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                    .accessibilityIdentifier("dashboard_label_errorMessage")
                }

                // Network Info Cards
                HStack(spacing: 16) {
                    ConnectionInfoCard()
                        .accessibilityIdentifier("dashboard_card_connection")
                    GatewayInfoCard()
                        .accessibilityIdentifier("dashboard_card_gateway")
                }
                .padding(.horizontal)

                QuickStatsBar()
                    .padding(.horizontal)
                    .accessibilityIdentifier("dashboard_card_quickStats")

                ISPInfoCard()
                    .padding(.horizontal)
                    .accessibilityIdentifier("dashboard_card_isp")

                // Monitoring Status
                if targets.isEmpty {
                    ContentUnavailableView(
                        "No Targets Configured",
                        systemImage: "target",
                        description: Text("Add network targets in the Targets section to start monitoring")
                    )
                    .accessibilityIdentifier("dashboard_label_noTargets")
                } else {
                    // Target Status Cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(targets) { target in
                            TargetStatusCard(
                                target: target,
                                measurement: session?.latestMeasurement(for: target.id)
                            )
                            .accessibilityIdentifier("dashboard_card_target_\(target.id)")
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, compactMode ? 8 : 16)
        }
        .background(
            ZStack {
                MacTheme.Colors.deckRecessed
                RadialGradient(
                    colors: [Color(hex: "1E3A5F").opacity(0.15), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 800
                )
            }
        )
        .navigationTitle("Dashboard")
    }
}

// MARK: - Target Status Card

struct InstrumentPanel: View {
    let session: MonitoringSession?
    
    var body: some View {
        HStack(spacing: 16) {
            // Widescreen Topology
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(.cyan)
                    Text("LOCAL LINK TOPOLOGY")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                }
                
                DashboardTopologyView(isMonitoring: session?.isMonitoring ?? false)
            }
            .padding(16)
            .background(MacTheme.Colors.deckBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MacTheme.Colors.deckBorder, lineWidth: 1))
            .frame(maxWidth: .infinity)
            
            // High-Resolution Jitter
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(.green)
                    Text("SIGNAL STABILITY (JITTER)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                }
                
                DashboardJitterView(isMonitoring: session?.isMonitoring ?? false)
            }
            .padding(16)
            .background(MacTheme.Colors.deckBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MacTheme.Colors.deckBorder, lineWidth: 1))
            .frame(width: 300)
        }
    }
}

struct DashboardTopologyView: View {
    let isMonitoring: Bool
    @State private var packetOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 0) {
            MacNode(icon: "macbook.gen3", label: "HOST")
            MacLink(active: isMonitoring, color: .cyan, offset: packetOffset)
            MacNode(icon: "server.rack", label: "GATEWAY")
            MacLink(active: isMonitoring, color: .green, offset: packetOffset)
            MacNode(icon: "globe.americas.fill", label: "WAN")
        }
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                packetOffset = 1.0
            }
        }
    }
}

struct MacNode: View {
    let icon: String
    let label: String
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(MacTheme.Colors.deckConsole)
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1), lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 18))
            }
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
        }
        .frame(width: 60)
    }
}

struct MacLink: View {
    let active: Bool
    let color: Color
    let offset: CGFloat
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 2)
                if active {
                    Rectangle().fill(color.opacity(0.2)).frame(height: 2)
                    Circle().fill(.white).frame(width: 4, height: 4)
                        .shadow(color: color, radius: 4)
                        .offset(x: -geo.size.width/2 + (geo.size.width * offset))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 44)
    }
}

struct DashboardJitterView: View {
    let isMonitoring: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<30, id: \.self) { i in
                let height = isMonitoring ? CGFloat.random(in: 4...24) : 4
                RoundedRectangle(cornerRadius: 1)
                    .fill(isMonitoring ? Color.green.opacity(0.6) : Color.white.opacity(0.1))
                    .frame(height: height)
                    .animation(.spring(response: 0.2, dampingFraction: 0.5), value: height)
            }
        }
        .frame(height: 24)
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
        .background(MacTheme.Colors.deckBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            // Scanner Sweep Animation
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.1), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 100)
                    .offset(x: geo.size.width * sweepOffset)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovering ? .white.opacity(0.3) : MacTheme.Colors.deckBorder, lineWidth: 1)
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
    
    DashboardView()
        .modelContainer(container)
        .environment(session)
}
#endif
