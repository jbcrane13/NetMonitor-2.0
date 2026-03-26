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

    /// Shared diagnostics card stack used across all layout modes.
    /// WiFi Signal is 2nd so the live sparkline is visible without scrolling.
    private func diagnosticsStack(gap: CGFloat) -> some View {
        VStack(spacing: gap) {
            LatencyAnalysisCard(
                session: session,
                gatewayLatencyHistory: gatewayLatencyHistory
            )
            .accessibilityIdentifier("network_detail_card_latency")

            WiFiSignalCard()
                .accessibilityIdentifier("network_detail_card_wifi_signal")

            ConnectivityCard(session: session, profileManager: profileManager)
                .accessibilityIdentifier("network_detail_card_connectivity")

            NetworkIntelCard()
                .accessibilityIdentifier("network_detail_card_intel")
        }
    }

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

    /// Responsive layout breakpoints:
    /// - Compact  (< 1200pt): single-column stacked layout
    /// - Standard (1200–1599pt): 2-column (44% diagnostics / 56% devices)
    /// - Wide     (≥ 1600pt): 3-column (ISP+gauge left, diagnostics center, devices right)
    private enum DashboardLayout {
        case compact, standard, wide

        init(width: CGFloat) {
            if width >= 1600 { self = .wide }
            else if width >= 1200 { self = .standard }
            else { self = .compact }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 10
            let pad: CGFloat = 14
            let availH = geo.size.height - pad * 2
            let layout = DashboardLayout(width: geo.size.width)
            let rowAHeight = max(160, availH * 0.26)

            // Row A is always anchored at the top: Gateway Health + Health Gauge
            VStack(spacing: gap) {
                HStack(alignment: .top, spacing: gap) {
                    ISPHealthCard(interfaceName: profile.interfaceName, uptime: uptimeViewModel)
                        .frame(maxWidth: .infinity)
                        .frame(height: rowAHeight)
                        .clipped()
                        .accessibilityIdentifier("network_detail_card_isp")

                    HealthGaugeCard()
                        .frame(width: rowAHeight, height: rowAHeight)
                        .accessibilityIdentifier("network_detail_row_health")
                }

                // Row B adapts based on layout breakpoint
                switch layout {
                case .wide:
                    // 3-column below: diagnostics | devices (split) | extra diagnostics overflow
                    let colWidth = (geo.size.width - pad * 2 - gap * 2) / 3
                    HStack(alignment: .top, spacing: gap) {
                        ScrollView(.vertical, showsIndicators: false) {
                            diagnosticsStack(gap: gap)
                        }
                        .frame(width: colWidth)

                        NetworkDevicesPanel(networkProfileID: profile.id)
                            .accessibilityIdentifier("network_detail_panel_devices")
                    }
                    .frame(height: max(0, availH - rowAHeight - gap))

                case .standard:
                    let leftWidth = max(340, geo.size.width * 0.44 - pad)
                    HStack(alignment: .top, spacing: gap) {
                        ScrollView(.vertical, showsIndicators: false) {
                            diagnosticsStack(gap: gap)
                        }
                        .frame(width: leftWidth)

                        NetworkDevicesPanel(networkProfileID: profile.id)
                            .accessibilityIdentifier("network_detail_panel_devices")
                    }
                    .frame(height: max(0, availH - rowAHeight - gap))

                case .compact:
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: gap) {
                            diagnosticsStack(gap: gap)

                            NetworkDevicesPanel(networkProfileID: profile.id)
                                .frame(height: 300)
                                .accessibilityIdentifier("network_detail_panel_devices")
                        }
                    }
                }
            }
            .padding(pad)
        }
        .navigationTitle(profile.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if session?.isMonitoring == true {
                        session?.stopMonitoring()
                    } else {
                        session?.startMonitoring()
                    }
                } label: {
                    if session?.isMonitoring == true {
                        Label("Stop Monitoring", systemImage: "stop.fill")
                    } else {
                        Label("Start Monitoring", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.bordered)
                .tint(session?.isMonitoring == true ? .red : .green)
                .accessibilityIdentifier("network_detail_button_monitoringToggle")
            }
        }
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
