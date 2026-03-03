import SwiftUI
import NetMonitorCore
import SwiftData

/// Per-network "war room" view — the main workhorse for a single network.
/// Layout: Row A full-width (activity + health gauge), then two columns below
/// (ISP/latency/connectivity left, scrollable device grid right).
struct NetworkDetailView: View {
    @Binding var profile: NetworkProfile

    @Environment(MonitoringSession.self)         private var session: MonitoringSession?
    @Environment(NetworkProfileManager.self)     private var profileManager: NetworkProfileManager?
    // periphery:ignore
    @Environment(DeviceDiscoveryCoordinator.self) private var deviceDiscovery: DeviceDiscoveryCoordinator?

    @Query private var targets: [NetworkTarget]

    private var gatewayLatencyHistory: [Double] {
        guard let session else { return [] }
        // Match any gateway-like target name
        if let gateway = targets.first(where: {
            $0.name.localizedCaseInsensitiveContains("gateway")
        }) {
            let history = session.recentLatencies[gateway.id] ?? []
            if !history.isEmpty { return history }
        }
        // Fall back to first ICMP target with data
        for target in targets where target.targetProtocol == .icmp {
            let history = session.recentLatencies[target.id] ?? []
            if !history.isEmpty { return history }
        }
        // Fall back to any target with latency data
        for (id, history) in session.recentLatencies {
            if !history.isEmpty { return history }
        }
        return []
    }

    var body: some View {
        VStack(spacing: 10) {
            // Row A: Internet Activity + Health Gauge
            HStack(alignment: .top, spacing: 10) {
                InternetActivityCard(session: session)
                    .accessibilityIdentifier("network_detail_row_activity")

                HealthGaugeCard()
                    .frame(width: 210)
                    .frame(maxHeight: 180)
                    .accessibilityIdentifier("network_detail_row_health")
            }
            .fixedSize(horizontal: false, vertical: true)

            // Row B: Left diagnostics stack + Right device grid
            HStack(alignment: .top, spacing: 10) {
                // Left column — ISP / Latency / Connectivity stacked
                VStack(spacing: 10) {
                    ISPHealthCard()
                        .accessibilityIdentifier("network_detail_card_isp")

                    LatencyAnalysisCard(
                        session: session,
                        gatewayLatencyHistory: gatewayLatencyHistory
                    )
                    .accessibilityIdentifier("network_detail_card_latency")

                    ConnectivityCard(session: session, profileManager: profileManager)
                        .accessibilityIdentifier("network_detail_card_connectivity")

                    NetworkIntelCard()
                        .accessibilityIdentifier("network_detail_card_intel")
                }
                .frame(minWidth: 300, idealWidth: 420)

                // Right column — device grid
                NetworkDevicesPanel(networkProfileID: profile.id)
                    .accessibilityIdentifier("network_detail_panel_devices")
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .macThemedBackground()
        .navigationTitle(profile.displayName)
        .onChange(of: profileManager?.profiles) {
            if let updated = profileManager?.profiles.first(where: { $0.id == profile.id }) {
                profile = updated
            }
        }
        .onAppear {
            // Auto-start monitoring so dashboard cards get live data
            if let session, !session.isMonitoring {
                session.startMonitoring()
            }
        }
    }
}

#if DEBUG
#Preview {
    let profile = NetworkProfile(
        interfaceName: "en0",
        ipAddress: "192.168.1.100",
        network: NetworkUtilities.IPv4Network(
            networkAddress: NetworkUtilities.ipv4ToUInt32("192.168.1.0")!,
            broadcastAddress: NetworkUtilities.ipv4ToUInt32("192.168.1.255")!,
            interfaceAddress: NetworkUtilities.ipv4ToUInt32("192.168.1.100")!,
            netmask: NetworkUtilities.ipv4ToUInt32("255.255.255.0")!
        ),
        connectionType: .wifi,
        name: "Home Network",
        gatewayIP: "192.168.1.1",
        subnet: "192.168.1.0/24",
        isLocal: true,
        discoveryMethod: .auto,
        lastScanned: Date().addingTimeInterval(-3600),
        deviceCount: 12,
        gatewayReachable: true
    )

    NetworkDetailView(profile: .constant(profile))
        .modelContainer(PreviewContainer().container)
}
#endif
