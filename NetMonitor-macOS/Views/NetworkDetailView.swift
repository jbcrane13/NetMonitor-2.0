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

    /// Computes uptime statistics from persisted records for display in ISPHealthCard.
    @State private var uptimeViewModel: UptimeViewModel?
    /// Shared by the health gauge and the Health Checks card so one refresh feeds both.
    @State private var healthViewModel = NetworkHealthScoreMacViewModel()
    /// The "since yesterday" brief, shared so navigation keeps its cache (#491 S6). Not view state:
    /// the app owns it, and the view only reads it.
    private var changeBrief: ChangeBriefMacViewModel { ChangeBriefMacViewModel.dashboard }

    /// Shared diagnostics card stack used across all layout modes.
    /// WiFi Signal is 2nd so the live sparkline is visible without scrolling.
    private func diagnosticsStack(gap: CGFloat) -> some View {
        VStack(spacing: gap) {
            if let brief = changeBrief.brief {
                ChangeBriefCard(brief: brief)
            }

            LatencyAnalysisCard(
                session: session,
                gatewayLatencyHistory: gatewayLatencyHistory
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("networkDetail_card_latency")

            WiFiSignalCard()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("networkDetail_card_wifiSignal")

            HealthChecklistCard(viewModel: healthViewModel) {
                Task { await refreshHealth() }
            }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("networkDetail_card_healthChecks")

            ConnectivityCard(session: session, profileManager: profileManager)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("networkDetail_card_connectivity")

            NetworkIntelCard()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("networkDetail_card_intel")
        }
    }

    private var gatewayLatencyHistory: [Double] {
        guard let session else { return [] }
        // Match any gateway-like target name
        if let gateway = targets.first(where: {
            $0.name.localizedCaseInsensitiveContains("gateway")
        }) {
            let history = session.recentLatencies[gateway.id] ?? []
            if !history.isEmpty {
                return history
            }
        }
        // Fall back to first ICMP target with data
        for target in targets where target.targetProtocol == .icmp {
            let history = session.recentLatencies[target.id] ?? []
            if !history.isEmpty {
                return history
            }
        }
        // Fall back to any target with latency data
        for (_, history) in session.recentLatencies where !history.isEmpty {
            return history
        }
        return []
    }

    /// Responsive layout breakpoints:
    /// - Compact  (< 900pt): single-column stacked layout
    /// - Standard (900–1599pt): 2-column (44% diagnostics / 56% devices)
    /// - Wide     (≥ 1600pt): 3-column (ISP+gauge left, diagnostics center, devices right)
    private enum DashboardLayout {
        case compact, standard, wide

        init(width: CGFloat) {
            if width >= 1600 {
                self = .wide
            } else if width >= 900 {
                self = .standard
            } else {
                self = .compact
            }
        }
    }

    /// What the health checks depend on: a change re-runs them.
    private struct HealthRefreshKey: Equatable {
        let profileID: UUID
        let lastScanTime: Date?
    }

    /// What the brief depends on: the network, a finished scan (its events are recorded by then),
    /// and the scan state, so a scan in progress asks nothing and its end asks again.
    private struct BriefRefreshKey: Equatable {
        let profileID: UUID
        let lastScanTime: Date?
        let isScanning: Bool
    }

    /// Gathers the Mac's own Wi-Fi and device readings, then refreshes the health score and checks.
    private func refreshHealth() async {
        let connection = try? await NetworkInfoService().getCurrentConnection()
        let isWiFi = connection?.connectionType == .wifi
        let deviceCount = deviceDiscovery.flatMap { $0.lastScanTime == nil ? nil : $0.discoveredDevices.count }
        await healthViewModel.refresh(
            gatewayIP: profile.gatewayIP.isEmpty ? nil : profile.gatewayIP,
            localInputs: HealthCheckInputs(
                wifiRSSI: isWiFi ? connection?.signalStrength : nil,
                deviceCount: deviceCount,
                linkSpeedMbps: connection?.linkSpeed.map(Double.init)
            ),
            networkProfileID: profileManager?.connectedLocalProfile?.id
        )
    }

    /// Live dashboard for the network this Mac is on.
    private var liveDashboard: some View {
        GeometryReader { geo in
            let gap: CGFloat = 10
            let pad: CGFloat = 14
            let availH = geo.size.height - pad * 2
            let layout = DashboardLayout(width: geo.size.width)
            let rowAHeight = max(160, availH * 0.26)

            // Row A is always anchored at the top: Gateway Health + Health Gauge
            VStack(spacing: gap) {
                HStack(alignment: .top, spacing: gap) {
                    ISPHealthCard(
                        interfaceName: profile.interfaceName,
                        gatewayAddress: profile.gatewayIP.isEmpty ? "—" : profile.gatewayIP,
                        uptime: uptimeViewModel
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowAHeight)
                        .clipped()
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("networkDetail_card_isp")

                    HealthGaugeCard(viewModel: healthViewModel)
                        .frame(width: rowAHeight, height: rowAHeight)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("networkDetail_row_health")
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
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("networkDetail_section_devices")
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
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("networkDetail_section_devices")
                    }
                    .frame(height: max(0, availH - rowAHeight - gap))

                case .compact:
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: gap) {
                            diagnosticsStack(gap: gap)

                            NetworkDevicesPanel(networkProfileID: profile.id)
                                .frame(height: 300)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("networkDetail_section_devices")
                        }
                    }
                }
            }
            .padding(pad)
        }
        // Re-run when the network changes and whenever a device scan finishes, so the
        // device count, router and Wi-Fi rows don't go stale.
        .task(id: HealthRefreshKey(profileID: profile.id, lastScanTime: deviceDiscovery?.lastScanTime)) {
            await refreshHealth()
        }
        // On appear and after each scan. Scan-completed handlers, which record the scan's events, run
        // before the coordinator publishes the end of the scan, so this sees them without waiting.
        .task(id: BriefRefreshKey(
            profileID: profile.id, lastScanTime: deviceDiscovery?.lastScanTime, isScanning: deviceDiscovery?.isScanning ?? false
        )) {
            await changeBrief.refresh(
                devices: deviceDiscovery?.discoveredDevices ?? [],
                networkProfileID: profile.id,
                isScanning: deviceDiscovery?.isScanning ?? false
            )
        }
    }

    /// A network this Mac is not on: live cards would describe the wrong network,
    /// so only the persisted device history is shown.
    private var inactiveNetworkLayout: some View {
        VStack(spacing: 10) {
            CardEmptyState(
                icon: "wifi.slash",
                title: "Not connected to \(profile.displayName)",
                description: "Live diagnostics show the network this Mac is on. Devices seen on this network are listed below."
            )
            .frame(maxWidth: .infinity)
            .macGlassCard(cornerRadius: 14, padding: 10)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("networkDetail_state_inactiveNetwork")

            NetworkDevicesPanel(networkProfileID: profile.id)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("networkDetail_section_devices")
        }
        .padding(14)
    }

    /// Live cards read the Mac's current connection, so they belong only to the
    /// auto-detected local network. Not `activeProfile`: scanning a manual
    /// network calls switchProfile and makes it "active" too (#336).
    static func showsLiveDiagnostics(for profile: NetworkProfile) -> Bool {
        profile.isLocal
    }

    var body: some View {
        Group {
            if Self.showsLiveDiagnostics(for: profile) {
                liveDashboard
            } else {
                inactiveNetworkLayout
            }
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
                .accessibilityIdentifier("networkDetail_button_monitoringToggle")
            }
        }
        .onChange(of: profileManager?.profiles) {
            if let updated = profileManager?.profiles.first(where: { $0.id == profile.id }) {
                profile = updated
            }
        }
        .onAppear {
            // Uptime stats for the local network. The app records its connectivity (#491 D8).
            if uptimeViewModel == nil, Self.showsLiveDiagnostics(for: profile) {
                let vm = UptimeViewModel(profileID: profile.id, modelContext: modelContext)
                vm.load()
                uptimeViewModel = vm
            }
            // Auto-start monitoring so dashboard cards get live data.
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
// swiftlint:disable:next force_unwrapping
            networkAddress: NetworkUtilities.ipv4ToUInt32("192.168.1.0")!,
// swiftlint:disable:next force_unwrapping
            broadcastAddress: NetworkUtilities.ipv4ToUInt32("192.168.1.255")!,
// swiftlint:disable:next force_unwrapping
            interfaceAddress: NetworkUtilities.ipv4ToUInt32("192.168.1.100")!,
// swiftlint:disable:next force_unwrapping
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
