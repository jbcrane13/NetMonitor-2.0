import SwiftUI
import NetMonitorCore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self) private var session: MonitoringSession?
    @Environment(DeviceDiscoveryCoordinator.self) private var deviceDiscovery: DeviceDiscoveryCoordinator?
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?
    @State private var selectedSection: SidebarSelection? = .section(.dashboard)
    @State private var localSession: MonitoringSession?
    @State private var selectedNetworkProfile: NetworkProfile?
    @State private var showingAddNetworkSheet = false

    private var activeSession: MonitoringSession? {
        session ?? localSession
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selectedSection,
                onAddNetwork: { showingAddNetworkSheet = true }
            )
        } detail: {
            detailView
        }
        .frame(minWidth: 1000, minHeight: 600)
        .sheet(isPresented: $showingAddNetworkSheet) {
            AddNetworkSheet()
        }
        .task {
            if session == nil && localSession == nil {
                let httpService = HTTPMonitorService()
                let icmpService = ICMPMonitorService()
                let tcpService = TCPMonitorService()
                localSession = MonitoringSession(
                    modelContext: modelContext,
                    httpService: httpService,
                    icmpService: icmpService,
                    tcpService: tcpService
                )
            }
        }
        .onChange(of: selectedSection, initial: true) {
            if case .network(let networkID) = selectedSection {
                selectedNetworkProfile = profileManager?.profiles.first(where: { $0.id == networkID })
            } else {
                selectedNetworkProfile = nil
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .network:
            if selectedNetworkProfile != nil {
                NetworkDetailView(
                    profile: Binding(
                        get: { selectedNetworkProfile! },
                        set: { selectedNetworkProfile = $0 }
                    )
                )
                .accessibilityIdentifier("detail_network")
            } else {
                Text("Network not found")
                    .accessibilityIdentifier("detail_network_not_found")
            }
        case .section(let section):
            sectionView(for: section)
        case .tool(let tool):
            toolView(for: tool)
        case nil:
            Text("Select a section")
                .accessibilityIdentifier("detail_empty")
        }
    }

    @ViewBuilder
    private func sectionView(for section: NavigationSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView(onSelectNetwork: { networkID in
                selectedSection = .network(networkID)
            })
            .accessibilityIdentifier("detail_dashboard")
        case .tools:
            ToolsView(selection: $selectedSection)
                .accessibilityIdentifier("detail_tools")
        case .settings:
            SettingsView()
                .accessibilityIdentifier("detail_settings")
        }
    }

    @ViewBuilder
    private func toolView(for tool: NetworkTool) -> some View {
        Group {
            switch tool {
            case .ping: PingToolView()
            case .traceroute: TracerouteToolView()
            case .portScanner: PortScannerToolView()
            case .dnsLookup: DNSLookupToolView()
            case .whois: WHOISToolView()
            case .speedTest: SpeedTestToolView()
            case .bonjourBrowser: BonjourBrowserToolView()
            case .wakeOnLan: WakeOnLanToolView()
            case .subnetCalculator: SubnetCalculatorToolView()
            case .worldPing: WorldPingToolView()
            case .geoTrace: GeoTraceView()
            case .sslMonitor: SSLCertificateMonitorView()
            case .wifiHeatmap: WiFiHeatmapToolView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    selectedSection = .section(.tools)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
        .modelContainer(PreviewContainer().container)
}
#endif
