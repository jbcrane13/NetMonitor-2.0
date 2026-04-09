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
    @State private var showQuickJump = false

    // periphery:ignore
    private var activeSession: MonitoringSession? {
        session ?? localSession
    }

    var body: some View {
        mainContent
            .modifier(KeyboardShortcutsModifier(
                selectedSection: $selectedSection,
                showQuickJump: $showQuickJump,
                onRescan: {
                    guard let deviceDiscovery, !deviceDiscovery.isScanning else { return }
                    deviceDiscovery.startScan()
                },
                onJumpToNetwork: { jumpToActiveNetwork() }
            ))
            .sheet(isPresented: $showQuickJump) {
                QuickJumpSheet(selection: $selectedSection, isPresented: $showQuickJump)
            }
    }

    // MARK: - Main Content (extracted to reduce body complexity)

    private var mainContent: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selectedSection,
                onAddNetwork: { showingAddNetworkSheet = true }
            )
        } detail: {
            detailView
                .macThemedBackground()
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

    // MARK: - ⌘1 handler (navigate to active network)
    private func jumpToActiveNetwork() {
        if let activeProfile = profileManager?.profiles.first(where: { $0.isLocal })
               ?? profileManager?.profiles.first {
            selectedSection = .network(activeProfile.id)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .network:
            if selectedNetworkProfile != nil {
                NetworkDetailView(
                    profile: Binding(
// swiftlint:disable:next force_unwrapping
                        get: { selectedNetworkProfile! },
                        set: { selectedNetworkProfile = $0 }
                    )
                )
                .accessibilityIdentifier("contentView_nav_network")
            } else {
                Text("Network not found")
                    .accessibilityIdentifier("contentView_label_networkNotFound")
            }
        case .section(let section):
            sectionView(for: section)
        case .tool(let tool):
            toolView(for: tool)
        case nil:
            Text("Select a section")
                .accessibilityIdentifier("contentView_label_empty")
        }
    }

    @ViewBuilder
    private func sectionView(for section: NavigationSection) -> some View {
        switch section {
        case .devices:
            DevicesView()
                .accessibilityIdentifier("contentView_nav_devices")
        case .tools:
            ToolsView(selection: $selectedSection)
                .accessibilityIdentifier("contentView_nav_tools")
        case .settings:
            SettingsView()
                .accessibilityIdentifier("contentView_nav_settings")
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
                .accessibilityIdentifier("contentView_button_back")
            }
        }
    }
}

// MARK: - Keyboard Shortcuts (extracted as ViewModifier to reduce type-checker pressure)

private struct KeyboardShortcutsModifier: ViewModifier {
    @Binding var selectedSection: SidebarSelection?
    @Binding var showQuickJump: Bool
    var onRescan: () -> Void
    var onJumpToNetwork: () -> Void

    func body(content: Content) -> some View {
        content
            .background { shortcutButtons }
    }

    // All shortcut buttons grouped in a single background overlay
    private var shortcutButtons: some View {
        Group {
            // ⌘1 — Jump to active network dashboard
            Button("", action: onJumpToNetwork)
                .keyboardShortcut("1", modifiers: .command)
                .accessibilityIdentifier("contentView_nav_jumpToNetwork")

            // ⌘2 — Devices list
            Button("") { selectedSection = .section(.devices) }
                .keyboardShortcut("2", modifiers: .command)
                .accessibilityIdentifier("contentView_nav_devicesShortcut")

            // ⌘3 — Tools
            Button("") { selectedSection = .section(.tools) }
                .keyboardShortcut("3", modifiers: .command)
                .accessibilityIdentifier("contentView_nav_toolsShortcut")

            // ⌘4 — Settings
            Button("") { selectedSection = .section(.settings) }
                .keyboardShortcut("4", modifiers: .command)
                .accessibilityIdentifier("contentView_nav_settingsShortcut")

            // ⌘R — Rescan network
            Button("", action: onRescan)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityIdentifier("contentView_button_rescan")

            // ⌘K — Quick jump to device
            Button("") { showQuickJump = true }
                .keyboardShortcut("k", modifiers: .command)
                .accessibilityIdentifier("contentView_nav_quickJump")

            // ⌘T — Quick tool launch
            Button("") { selectedSection = .section(.tools) }
                .keyboardShortcut("t", modifiers: .command)
                .accessibilityIdentifier("contentView_nav_launchTools")
        }
        .hidden()
    }
}

#if DEBUG
#Preview {
    ContentView()
        .modelContainer(PreviewContainer().container)
}
#endif
