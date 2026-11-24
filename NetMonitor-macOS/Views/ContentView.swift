import SwiftUI
import NetMonitorCore
import SwiftData

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
                onJumpToNetwork: { jumpToActiveNetwork() }
            ))
            .focusedSceneValue(\.scanNetworkAction) { [deviceDiscovery, selectedNetworkProfile] in
                guard let deviceDiscovery else { return }
                Self.scan(with: deviceDiscovery, selected: selectedNetworkProfile)
            }
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
            AddNetworkSheet(onAdded: { selectedSection = .network($0.id) })
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
        .onChange(of: NotificationRouter.shared.pending, initial: true) { _, route in
            // View Details on an alert (#478).
            guard let route else { return }
            NotificationRouter.shared.pending = nil
            // Only the saved devices at the alert's address.
            var devices: [LocalDevice] = []
            if case let .device(ip, _) = route {
                devices = (try? modelContext.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.ipAddress == ip }))) ?? []
            }
            let target = NotificationRouter.selection(
                for: route, devices: devices, localNetworkID: profileManager?.localProfile?.id
            )
            NotificationRouter.shared.deviceToSelect = target.device
            if let section = target.section {
                selectedSection = section
            }
        }
        .onChange(of: profileManager?.localProfile?.id) { oldID, newID in
            // Joining another network gives the local profile a new id and drops the old one;
            // keep an open local dashboard on the network the Mac is on now.
            selectedSection = Self.followLocalNetwork(selectedSection, from: oldID, to: newID)
        }
        .onAppear {
            // Launch into the active (local) network dashboard
            if selectedSection == nil,
               let activeProfile = profileManager?.localProfile
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

    /// The sidebar selection after the local profile's id changed from `oldID` to `newID`:
    /// the old local network's dashboard moves to the new one, anything else stays put.
    static func followLocalNetwork(
        _ selection: SidebarSelection?,
        from oldID: UUID?,
        to newID: UUID?
    ) -> SidebarSelection? {
        guard let oldID, let newID, oldID != newID, selection == .network(oldID) else { return selection }
        return .network(newID)
    }

    // MARK: - ⌘1 handler (navigate to active network)
    private func jumpToActiveNetwork() {
        if let activeProfile = profileManager?.localProfile
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
                // A new subnet is a different dashboard: rebuild it so its gateway monitor
                // follows the network the Mac is on (#359).
                .id(selectedNetworkProfile?.subnet)
                .accessibilityElement(children: .contain)
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
            case .wifiHeatmap: WiFiHeatmapView(pendingSurveyURL: pendingSurveyURL)
            case .portForwards: PortForwardsToolView()
            case .timeline: TimelineView()
            case .securityReadout: SecurityReadoutView()
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

extension ContentView {
    /// File ▸ Scan Network and ⌘R (#444): scans the network dashboard on screen, like its Scan
    /// button, else the coordinator's current network.
    static func scan(with coordinator: DeviceDiscoveryCoordinator, selected profile: NetworkProfile?) {
        coordinator.rescan(.user(profile))
    }
}

// MARK: - Keyboard Shortcuts (extracted as ViewModifier to reduce type-checker pressure)

private struct KeyboardShortcutsModifier: ViewModifier {
    @Binding var selectedSection: SidebarSelection?
    @Binding var showQuickJump: Bool
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

            // ⌘R is the File ▸ Scan Network command (MenuBarCommands, #444).

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
