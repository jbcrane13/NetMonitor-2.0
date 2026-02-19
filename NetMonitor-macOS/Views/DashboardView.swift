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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: target.targetProtocol.iconName)
                    .foregroundStyle(.secondary)

                Text(target.name)
                    .font(.headline)

                Spacer()

                // Status Indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            // Host
            Text(target.host)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Metrics
            if let measurement = measurement {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latency")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let latency = measurement.latency {
                            Text(latency < 1 ? "<1 ms" : String(format: "%.0f ms", latency))
                                .font(.title3)
                                .fontWeight(.semibold)
                        } else {
                            Text("—")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Status")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(measurement.isReachable ? "Online" : "Offline")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(measurement.isReachable ? .green : .red)
                    }
                }
            } else {
                Text("Click 'Start Monitoring' to check status")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
