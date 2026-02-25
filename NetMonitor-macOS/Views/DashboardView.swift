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
        .navigationTitle("Dashboard")
    }
}

// MARK: - Target Status Card

struct TargetStatusCard: View {
    let target: NetworkTarget
    let measurement: TargetMeasurement?

    // Simulate history based on latest measurement
    var simulatedHistory: [Double] {
        let base = measurement?.latency ?? 20.0
        return (0..<15).map { _ in max(1, base + Double.random(in: -5...5)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: target.targetProtocol.iconName)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(target.name)
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                // Status Indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.8), radius: 4, x: 0, y: 0)
            }

            // Host
            Text(target.host)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            // Sparkline
            HistorySparkline(data: simulatedHistory, color: statusColor, lineWidth: 1.5, showPulse: true)
                .frame(height: 30)
                .padding(.vertical, 4)

            // Metrics
            if let measurement = measurement {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LATENCY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        if let latency = measurement.latency {
                            Text(latency < 1 ? "<1 ms" : String(format: "%.0f ms", latency))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                        } else {
                            Text("—")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("STATUS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Text(measurement.isReachable ? "ONLINE" : "OFFLINE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(measurement.isReachable ? .green : .red)
                    }
                }
            } else {
                Text("Waiting for data...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(white: 0.1)) // Dark charcoal background
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
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
