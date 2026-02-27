import SwiftUI
import NetMonitorCore
import SwiftData

// MARK: - DashboardView

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self)     private var session: MonitoringSession?
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?

    @Query private var targets: [NetworkTarget]

    @State private var showingAddTarget = false

    var body: some View {
        GeometryReader { geo in
            let h       = geo.size.height
            let gap     = CGFloat(10)
            let rowA    = h * 0.28
            let rowB    = h * 0.22
            let rowC    = h * 0.20
            let rowD    = h - rowA - rowB - rowC - gap * 3

            VStack(spacing: gap) {
                // ── Row A: Internet Activity + Health Gauge ──────────────
                HStack(spacing: gap) {
                    InternetActivityCard(session: session)
                        .frame(height: rowA)
                        .accessibilityIdentifier("dashboard_row_activity")

                    HealthGaugeCard()
                        .frame(width: 210, height: rowA)
                        .accessibilityIdentifier("dashboard_row_health")
                }

                // ── Row B: ISP Health + Latency Analysis ─────────────────
                HStack(spacing: gap) {
                    ISPHealthCard()
                        .frame(height: rowB)
                        .accessibilityIdentifier("dashboard_row_isp")

                    LatencyAnalysisCard(session: session)
                        .frame(height: rowB)
                        .accessibilityIdentifier("dashboard_row_latency")
                }

                // ── Row C: Connectivity + Active Devices ──────────────────
                HStack(spacing: gap) {
                    ConnectivityCard(session: session, profileManager: profileManager)
                        .frame(height: rowC)
                        .accessibilityIdentifier("dashboard_row_connectivity")

                    ActiveDevicesCard(session: session)
                        .frame(height: rowC)
                        .accessibilityIdentifier("dashboard_row_devices")
                }

                // ── Row D: Target Monitoring ──────────────────────────────
                TargetMonitoringSection(targets: targets, session: session, showingAddTarget: $showingAddTarget)
                    .frame(height: rowD)
                    .accessibilityIdentifier("dashboard_row_targets")
                    .sheet(isPresented: $showingAddTarget) {
                        AddTargetSheet()
                    }
            }
            .padding(14)
        }
        .macThemedBackground()
        .navigationTitle("Dashboard")
        .task {
            await seedDefaultTargetsIfNeeded()
            if let session, !session.isMonitoring {
                session.startMonitoring()
            }
        }
    }

    private func seedDefaultTargetsIfNeeded() async {
        guard targets.isEmpty else { return }
        let seeds: [(String, String)] = [
            ("Local Gateway", "192.168.1.1"),
            ("Google DNS",    "8.8.8.8"),
            ("Cloudflare",    "1.1.1.1"),
        ]
        for (name, host) in seeds {
            modelContext.insert(NetworkTarget(name: name, host: host, targetProtocol: .icmp))
        }
        try? modelContext.save()
    }
}

// MARK: - TargetMonitoringSection

private struct TargetMonitoringSection: View {
    let targets: [NetworkTarget]
    let session: MonitoringSession?
    @Binding var showingAddTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(MacTheme.Colors.info).frame(width: 5, height: 5)
                Text("TARGET MONITORING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                if let session {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(session.isMonitoring ? MacTheme.Colors.success : Color.gray)
                            .frame(width: 6, height: 6)
                            .shadow(
                                color: (session.isMonitoring
                                        ? MacTheme.Colors.success : Color.gray).opacity(0.7),
                                radius: 3
                            )
                        Text("\(targets.count) targets \(session.isMonitoring ? "active" : "stopped")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Button {
                            session.isMonitoring
                                ? session.stopMonitoring()
                                : session.startMonitoring()
                        } label: {
                            Label(
                                session.isMonitoring ? "STOP" : "START",
                                systemImage: session.isMonitoring ? "stop.fill" : "play.fill"
                            )
                            .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(session.isMonitoring ? MacTheme.Colors.error : MacTheme.Colors.success)
                        .controlSize(.small)
                        .accessibilityIdentifier("dashboard_targets_toggleButton")
                    }
                }
            }

            if targets.isEmpty {
                NoTargetsView(onAdd: { showingAddTarget = true })
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 10) {
                    ForEach(targets) { target in
                        TargetStatusCard(
                            target: target,
                            measurement: session?.latestMeasurement(for: target.id)
                        )
                    }
                }
            }
        }
        .macGlassCard(cornerRadius: 14, padding: 12)
    }
}

// MARK: - TargetStatusCard

struct TargetStatusCard: View {
    let target: NetworkTarget
    let measurement: TargetMeasurement?

    @State private var isHovering = false

    private var simulatedHistory: [Double] {
        let base = measurement?.latency ?? 5.0
        var seed = UInt64(bitPattern: Int64(target.id.hashValue)) &+ 1
        return (0..<20).map { _ in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = Double(seed >> 33) / Double(UInt32.max)
            return max(0.5, base + (r - 0.5) * base * 0.6)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: target.targetProtocol.iconName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(target.name.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.8),
                            radius: isHovering ? 5 : 2)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.white.opacity(0.03))

            Divider().background(MacTheme.Colors.glassBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text(target.host)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.28))
                    HistorySparkline(
                        data: simulatedHistory,
                        color: statusColor,
                        lineWidth: 1.5,
                        showPulse: true
                    )
                    .padding(3)
                }
                .frame(height: 30)
                .accessibilityLabel("Latency history for \(target.name)")

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("LATENCY")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        if let lat = measurement?.latency {
                            Text(String(format: "%.1fms", lat))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(MacTheme.Colors.latencyColor(ms: lat))
                        } else {
                            Text("—")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("SIGNAL")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(signalText)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(signalColor)
                    }
                }
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 10)
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius, padding: 0)
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.Layout.cardCornerRadius)
                .stroke(isHovering ? Color.white.opacity(0.22) : Color.clear,
                        lineWidth: 0.5)
        )
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("dashboard_target_\(target.host)")
    }

    private var statusColor: Color {
        guard let m = measurement else { return .gray }
        return m.isReachable ? MacTheme.Colors.success : MacTheme.Colors.error
    }

    private var signalText: String {
        guard let m = measurement else { return "—" }
        return m.isReachable ? "NOMINAL" : "LOST"
    }

    private var signalColor: Color {
        guard let m = measurement else { return MacTheme.Colors.textSecondary }
        return m.isReachable ? MacTheme.Colors.success : MacTheme.Colors.error
    }
}

// MARK: - NoTargetsView

struct NoTargetsView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("NO TARGETS")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.secondary)
            Button("ADD FIRST TARGET", action: onAdd)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(MacTheme.Colors.crystalBase)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
