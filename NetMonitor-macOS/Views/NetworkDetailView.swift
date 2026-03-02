import SwiftUI
import NetMonitorCore
import SwiftData

/// Per-network detail view — shows discovered devices for a single network profile.
struct NetworkDetailView: View {
    @Binding var profile: NetworkProfile

    @Environment(NetworkProfileManager.self)      private var profileManager: NetworkProfileManager?
    @Environment(DeviceDiscoveryCoordinator.self) private var deviceDiscovery: DeviceDiscoveryCoordinator?

    @State private var showAddTarget = false
    @State private var monitorInterval: TimeInterval = 5.0

    private let monitorIntervals: [(String, TimeInterval)] = [
        ("1s", 1), ("5s", 5), ("10s", 10), ("30s", 30), ("1m", 60), ("5m", 300)
    ]

    var body: some View {
        NetworkDevicesPanel(networkProfileID: profile.id)
            .accessibilityIdentifier("network_detail_panel_devices")
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
            .onChange(of: profileManager?.profiles) {
                if let updated = profileManager?.profiles.first(where: { $0.id == profile.id }) {
                    profile = updated
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
