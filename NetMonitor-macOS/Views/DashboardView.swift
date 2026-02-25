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
            VStack(spacing: compactMode ? 12 : 20) {
                // Header
                HStack {
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
                                session.isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                                systemImage: session.isMonitoring ? "stop.circle.fill" : "play.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(session.isMonitoring ? .red : .green)
                        .accessibilityIdentifier("dashboard_button_monitoring_toggle")
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
        .background(MacTheme.Colors.deckRecessed)
        .navigationTitle("Dashboard")
    }
}

// MARK: - Target Status Card

struct TargetStatusCard: View {
    let target: NetworkTarget
    let measurement: TargetMeasurement?

    @State private var isHovering = false

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
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHovering ? .white.opacity(0.2) : MacTheme.Colors.deckBorder, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
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
