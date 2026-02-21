import SwiftUI
import NetMonitorCore

struct NetworkDetailView: View {
    @Binding var profile: NetworkProfile
    @Environment(\.appAccentColor) private var accentColor

    @State private var isEditing = false
    @State private var editedName: String = ""

    let scanAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                networkInfoCard
                discoveryCard
                devicesCard
                actionsSection
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        saveChanges()
                    } else {
                        startEditing()
                    }
                    isEditing.toggle()
                }
                .accessibilityIdentifier("network_detail_button_edit")
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 64, height: 64)

                Image(systemName: profile.connectionType.iconName)
                    .font(.title)
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Network Name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("network_detail_field_name")
                } else {
                    Text(profile.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Text(profile.subnetCIDR)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("network_detail_card_header")
    }

    private var networkInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Network Information", systemImage: "network")
                .font(.headline)

            Divider()

            infoRow(label: "Gateway IP", value: profile.gatewayIP, monospace: true)

            infoRow(label: "Subnet CIDR", value: profile.subnetCIDR, monospace: true)

            infoRow(label: "Interface", value: profile.interfaceName, monospace: true)

            HStack {
                Text("Connection Type")
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Label(profile.connectionType.displayName, systemImage: profile.connectionType.iconName)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("network_detail_card_networkInfo")
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Discovery", systemImage: "magnifyingglass")
                .font(.headline)

            Divider()

            infoRow(label: "Method", value: discoveryMethodLabel)

            if let lastScanned = profile.lastScanned {
                infoRow(label: "Last Scanned", value: relativeTime(from: lastScanned))
            } else {
                infoRow(label: "Last Scanned", value: "Never")
            }

            infoRow(label: "Local Network", value: profile.isLocal ? "Yes" : "No")
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("network_detail_card_discovery")
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Devices", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.headline)

            Divider()

            if let deviceCount = profile.deviceCount {
                infoRow(label: "Device Count", value: "\(deviceCount)")
            } else {
                infoRow(label: "Device Count", value: "Not scanned")
            }

            infoRow(label: "Host Capacity", value: "\(profile.hostCount) addresses")
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("network_detail_card_devices")
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Actions", systemImage: "bolt")
                .font(.headline)

            Divider()

            Button {
                scanAction()
            } label: {
                Label("Scan This Network", systemImage: "network")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("network_detail_button_scan")
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("network_detail_card_actions")
    }

    private func infoRow(label: String, value: String, monospace: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(value)
                .fontDesign(monospace ? .monospaced : .default)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var discoveryMethodLabel: String {
        switch profile.discoveryMethod {
        case .auto: "Automatic"
        case .manual: "Manual"
        case .companion: "Companion"
        }
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) minutes ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) hours ago" }
        return "\(Int(interval / 86400)) days ago"
    }

    private func startEditing() {
        editedName = profile.name
    }

    private func saveChanges() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            profile.name = trimmed
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
        deviceCount: 12
    )

    NetworkDetailView(profile: .constant(profile)) {
        print("Scan action triggered")
    }
}
#endif
