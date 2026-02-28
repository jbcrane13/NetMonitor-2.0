import SwiftUI
import NetMonitorCore
import SwiftData

// MARK: - DashboardView

struct DashboardView: View {
    var onSelectNetwork: ((UUID) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self)     private var session: MonitoringSession?
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?

    @Query private var targets: [NetworkTarget]
    @Query(sort: \LocalDevice.lastSeen, order: .reverse) private var devices: [LocalDevice]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                dashboardHeader

                // Network summary cards grid
                networkCardsGrid

                // Combined Internet Activity chart
                combinedActivitySection
            }
            .padding(16)
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

    // MARK: - Header

    private var dashboardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(MacTheme.Colors.info)
                        .frame(width: 5, height: 5)
                    Text("ALL NETWORKS OVERVIEW")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.4)
                }
                Text("\(profileManager?.profiles.count ?? 0) networks monitored")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Aggregate target status
            if let session {
                let online  = session.onlineTargetCount
                let total   = online + session.offlineTargetCount
                if total > 0 {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(online == total ? MacTheme.Colors.success : MacTheme.Colors.warning)
                            .frame(width: 6, height: 6)
                        Text("\(online)/\(total) targets online")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Network Cards Grid

    private var networkCardsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)],
            spacing: 12
        ) {
            if let profiles = profileManager?.profiles, !profiles.isEmpty {
                ForEach(profiles) { profile in
                    NetworkSummaryCard(
                        profile: profile,
                        isActive: profileManager?.activeProfile?.id == profile.id,
                        deviceCount: devices.filter { $0.networkProfileID == profile.id }.count,
                        session: session
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectNetwork?(profile.id)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Networks",
                    systemImage: "network.slash",
                    description: Text("Add a network using the + button in the sidebar")
                )
                .padding(24)
            }
        }
        .accessibilityIdentifier("dashboard_networks_grid")
    }

    // MARK: - Combined Activity

    private var combinedActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(MacTheme.Colors.info)
                    .frame(width: 5, height: 5)
                Text("INTERNET ACTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
            }

            InternetActivityCard(session: session)
                .frame(height: 160)
                .accessibilityIdentifier("dashboard_combined_activity")
        }
    }

    // MARK: - Seeding

    private func seedDefaultTargetsIfNeeded() async {
        // Update existing gateway target if IP changed (e.g. network switch)
        if let gatewayTarget = targets.first(where: { $0.name == "Local Gateway" }),
           let detectedGateway = NetworkUtilities.detectDefaultGateway(),
           gatewayTarget.host != detectedGateway {
            gatewayTarget.host = detectedGateway
            try? modelContext.save()
        }

        guard targets.isEmpty else { return }
        let gatewayIP = NetworkUtilities.detectDefaultGateway() ?? "192.168.1.1"
        let seeds: [(String, String)] = [
            ("Local Gateway", gatewayIP),
            ("Google DNS",    "8.8.8.8"),
            ("Cloudflare",    "1.1.1.1"),
        ]
        for (name, host) in seeds {
            modelContext.insert(NetworkTarget(name: name, host: host, targetProtocol: .icmp))
        }
        try? modelContext.save()
    }
}

// MARK: - NetworkSummaryCard

private struct NetworkSummaryCard: View {
    let profile: NetworkProfile
    let isActive: Bool
    let deviceCount: Int
    let session: MonitoringSession?

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: status dot + name + active badge
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? MacTheme.Colors.success : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .shadow(color: isActive ? MacTheme.Colors.success.opacity(0.6) : .clear, radius: 4)

                Text(profile.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                if isActive {
                    Text("ACTIVE")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MacTheme.Colors.success.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                } else {
                    Text("IDLE")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 3))
                }
            }

            Divider()
                .opacity(0.4)

            // Metrics
            VStack(alignment: .leading, spacing: 6) {
                metricRow(
                    icon: "desktopcomputer",
                    label: deviceCount > 0 ? "\(deviceCount) devices" : "Not scanned"
                )

                metricRow(
                    icon: "network",
                    label: profile.gatewayIP
                )

                metricRow(
                    icon: profile.connectionType.iconName,
                    label: profile.connectionType.displayName
                )

                if let lastScanned = profile.lastScanned {
                    metricRow(
                        icon: "clock",
                        label: "Scanned " + relativeTime(from: lastScanned)
                    )
                } else {
                    metricRow(icon: "clock", label: "Never scanned")
                }
            }

            // Navigate hint
            HStack {
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isHovering ? MacTheme.Colors.info : Color.clear)
            }
        }
        .padding(14)
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius, padding: 0)
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.Layout.cardCornerRadius)
                .stroke(
                    isHovering ? MacTheme.Colors.info.opacity(0.4) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .accessibilityIdentifier("dashboard_network_card_\(profile.displayName.lowercased())")
    }

    private func metricRow(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60     { return "just now" }
        if interval < 3600   { return "\(Int(interval / 60))m ago" }
        if interval < 86400  { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

#if DEBUG
#Preview {
    DashboardView()
        .modelContainer(PreviewContainer().container)
        .environment(NetworkProfileManager())
}
#endif
