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
    @Environment(DeviceDiscoveryCoordinator.self) private var deviceDiscovery: DeviceDiscoveryCoordinator?

    @Query private var targets: [NetworkTarget]

    private var gatewayLatencyHistory: [Double] {
        guard let session else { return [] }
        if let gateway = targets.first(where: { $0.name == "Local Gateway" }) {
            return session.recentLatencies[gateway.id] ?? []
        }
        if let firstICMP = targets.first(where: { $0.targetProtocol == .icmp }) {
            return session.recentLatencies[firstICMP.id] ?? []
        }
        return []
    }

    @State private var resolvedGatewayDomain: String? = nil
    @State private var showAddTarget = false
    @State private var monitorInterval: TimeInterval = 5.0

    private let monitorIntervals: [(String, TimeInterval)] = [
        ("1s", 1), ("5s", 5), ("10s", 10), ("30s", 30), ("1m", 60), ("5m", 300)
    ]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 10
            let rowAHeight = geo.size.height * 0.28

            VStack(spacing: gap) {
                // Row A: ISP Health (hero) + Health Gauge
                HStack(spacing: gap) {
                    ISPHealthCard(
                            gatewayAddress: profile.gatewayIP ?? "—",
                            resolvedDomain: resolvedGatewayDomain
                        )
                        .accessibilityIdentifier("network_detail_card_isp")

                    HealthGaugeCard()
                        .frame(width: 210)
                        .accessibilityIdentifier("network_detail_row_health")
                }
                .frame(height: rowAHeight)

                // Row B: Left diagnostics stack + Right device grid
                HStack(alignment: .top, spacing: gap) {
                    // Left column — Activity / Latency / Connectivity stacked
                    VStack(spacing: gap) {
                        InternetActivityCard(session: session)
                            .accessibilityIdentifier("network_detail_row_activity")

                        LatencyAnalysisCard(
                            session: session,
                            gatewayLatencyHistory: gatewayLatencyHistory
                        )
                        .accessibilityIdentifier("network_detail_card_latency")

                        ConnectivityCard(session: session, profileManager: profileManager)
                            .accessibilityIdentifier("network_detail_card_connectivity")
                    }
                    .frame(width: geo.size.width * 0.42 - gap)

                    // Right column — device grid
                    NetworkDevicesPanel(networkProfileID: profile.id)
                        .accessibilityIdentifier("network_detail_panel_devices")
                }
                .frame(maxHeight: .infinity)
            }
            .padding(14)
        }
        .macThemedBackground()
        .navigationTitle(profile.displayName)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Scan button
                Button {
                    Task {
                        deviceDiscovery?.scanNetwork(profile)
                    }
                } label: {
                    Label("Scan Network", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(deviceDiscovery?.isScanning == true)
                .help("Scan for devices on this network")

                // Monitor interval picker
                Menu {
                    ForEach(monitorIntervals, id: \.1) { label, interval in
                        Button {
                            monitorInterval = interval
                            // TODO: update monitoring interval
                        } label: {
                            HStack {
                                Text(label)
                                if monitorInterval == interval {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Monitor", systemImage: "timer")
                }
                .help("Set monitoring interval")

                // Add target button
                Button {
                    showAddTarget = true
                } label: {
                    Label("Set Target", systemImage: "target")
                }
                .help("Add a monitoring target")
            }
        }
        .sheet(isPresented: $showAddTarget) {
            AddTargetSheet()
                .frame(minWidth: 400, minHeight: 300)
        }
        .task {
            // Resolve gateway domain
            let gw = profile.gatewayIP; if !gw.isEmpty {
                resolvedGatewayDomain = await resolveHostname(for: gw)
            }
        }
        .onChange(of: profileManager?.profiles) {
            if let updated = profileManager?.profiles.first(where: { $0.id == profile.id }) {
                profile = updated
            }
        }
    }
}

    private func resolveHostname(for ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_flags = AI_NUMERICHOST
                var res: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(ip, nil, &hints, &res) == 0, let addr = res else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { freeaddrinfo(res) }
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr.pointee.ai_addr, addr.pointee.ai_addrlen,
                               &hostname, socklen_t(hostname.count),
                               nil, 0, 0) == 0 {
                    let name = String(cString: hostname)
                    // Only return if it's actually a domain, not just the IP repeated
                    continuation.resume(returning: name != ip ? name : nil)
                } else {
                    continuation.resume(returning: nil)
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
