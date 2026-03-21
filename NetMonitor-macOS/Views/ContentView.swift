import SwiftUI
import NetMonitorCore

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self) private var session: MonitoringSession?
    // periphery:ignore
    @Environment(DeviceDiscoveryCoordinator.self) private var deviceDiscovery: DeviceDiscoveryCoordinator?
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?
    @State private var selectedSection: SidebarSelection?
    @State private var localSession: MonitoringSession?
    @State private var selectedNetworkProfile: NetworkProfile?
    @State private var showingAddNetworkSheet = false
    @State private var pendingSurveyURL: URL?

    // periphery:ignore
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
        .frame(minWidth: 1000, idealWidth: 1400, maxWidth: 2200, minHeight: 600, idealHeight: 900, maxHeight: 1600)
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
        .onAppear {
            // Launch into the active (local) network dashboard
            if selectedSection == nil,
               let activeProfile = profileManager?.profiles.first(where: { $0.isLocal })
                   ?? profileManager?.profiles.first {
                selectedSection = .network(activeProfile.id)
            }
        }
        .onOpenURL { url in
            // Handle Finder double-click / AirDrop for heatmap files
            if url.pathExtension == "netmonsurvey" || url.pathExtension == "netmonblueprint" {
                pendingSurveyURL = url
                selectedSection = .tool(.wifiHeatmap)
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
        case .devices:
            DevicesView()
                .accessibilityIdentifier("detail_devices")
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
            case .wifiHeatmap: WiFiHeatmapView()
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
