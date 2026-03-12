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
    @Environment(\.modelContext)                 private var modelContext

    @Query private var targets: [NetworkTarget]

    /// Persists connectivity transitions and latency samples for this profile.
    @State private var connectivityMonitor: ConnectivityMonitor?
    /// Computes uptime statistics from persisted records for display in ISPHealthCard.
    @State private var uptimeViewModel: UptimeViewModel?

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
        GeometryReader { geo in
            let gap: CGFloat = 10
            let pad: CGFloat = 14
            let availH = geo.size.height - pad * 2
            let rowAHeight = max(160, availH * 0.26)
            // Left column: 44% of width. Device panel gets the rest (~56%), still wide for hostnames.
            let leftWidth = max(340, geo.size.width * 0.44 - pad)

            VStack(spacing: gap) {
                // Row A: Network Health Hero (promoted from side gauge)
                HealthGaugeCard()
                    .frame(height: rowAHeight)
                    .accessibilityIdentifier("network_detail_row_health")

                // Row B: Left diagnostics stack + Right device grid
                HStack(alignment: .top, spacing: gap) {
                    // Left column — scrollable so all cards are reachable on smaller screens
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: gap) {
                            ISPHealthCard(interfaceName: profile.interfaceName, uptime: uptimeViewModel)
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

                            WiFiSignalCard()
                                .accessibilityIdentifier("network_detail_card_wifi_signal")
                        }
                    }
                    .frame(width: leftWidth)

                    // Right column — device grid
                    NetworkDevicesPanel(networkProfileID: profile.id)
                        .accessibilityIdentifier("network_detail_panel_devices")
                }
                .frame(height: max(0, availH - rowAHeight - gap))
            }
            .padding(pad)
        }
        .macThemedBackground()
        .navigationTitle(profile.displayName)
        .onChange(of: profileManager?.profiles) {
            if let updated = profileManager?.profiles.first(where: { $0.id == profile.id }) {
                profile = updated
            }
        }
        .onAppear {
            // Initialize connectivity monitoring and uptime stats if not yet set up.
            if connectivityMonitor == nil {
                let monitor = ConnectivityMonitor(
                    profileID: profile.id,
                    gatewayIP: profile.gatewayIP,
                    modelContext: modelContext
                )
                connectivityMonitor = monitor
                let vm = UptimeViewModel(profileID: profile.id, modelContext: modelContext)
                vm.load()
                uptimeViewModel = vm
            }
            // Auto-start monitoring so dashboard cards get live data.
            if let session, !session.isMonitoring {
                session.startMonitoring()
            }
        }
        .task(priority: .utility) {
            // Starts NWPathMonitor and periodic latency sampling.
            // Automatically cancelled when the view disappears.
            await connectivityMonitor?.start()
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
