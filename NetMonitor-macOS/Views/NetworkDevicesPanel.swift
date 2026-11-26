import SwiftUI
import NetMonitorCore
import SwiftData

/// Full-height scrollable device grid scoped to a single network profile.
/// Embedded in NetworkDetailView as the right-column panel.
struct NetworkDevicesPanel: View {
    let networkProfileID: UUID?

    @Environment(DeviceDiscoveryCoordinator.self) private var coordinator: DeviceDiscoveryCoordinator?
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?
    @Environment(\.presence) private var presence
    @Environment(\.modelContext) private var modelContext
    @Query private var devices: [LocalDevice]

    init(networkProfileID: UUID?) {
        self.networkProfileID = networkProfileID
        // Push the profile predicate into the store so the 500-row cap applies to
        // this profile's devices rather than the global LocalDevice table.
        _devices = Query(LocalDeviceQueries.forProfile(networkProfileID), animation: .default)
    }

    @State private var searchText: String = ""
    @AppStorage("netmonitor.devicesPanel.sortOrder") private var sortOrder: DeviceSortOrder = .ipAddress
    @State private var selectedDevice: LocalDevice?
    @State private var showFullDevicesView = false

    /// Sort orders shown in this panel's picker — a subset of the six Core cases.
    static let sortOptions: [DeviceSortOrder] = [.status, .name, .ipAddress, .lastSeen]

    /// What the Scan button should do.
    enum ScanTarget: Equatable {
        case network(NetworkProfile)
        case startScan
        case none
    }

    /// Resolves the Scan button's target from the panel's own profile ID.
    /// A nil ID (global Devices view) rescans the last-scanned network, or starts a default scan.
    /// An ID that matches no known profile does nothing.
    static func scanTarget(
        panelProfileID: UUID?,
        profiles: [NetworkProfile],
        lastScanned: NetworkProfile?
    ) -> ScanTarget {
        if let panelProfileID {
            // Never fall back to another network: that is what made B's Scan rescan A (#347).
            guard let profile = profiles.first(where: { $0.id == panelProfileID }) else { return .none }
            return .network(profile)
        }
        if let lastScanned {
            return .network(lastScanned)
        }
        return .startScan
    }

    /// One entry per device (#594): the 500 most recent devices (paged by device), projected, then
    /// searched and sorted.
    private var filteredDevices: [DeviceProjection] {
        // `devices` (the query) only triggers the refresh; the rows are paged by device.
        DeviceList.devices(
            devices.isEmpty ? [] : LocalDeviceQueries.recentDevices(network: networkProfileID, in: modelContext).flatMap(\.members),
            // Past devices stay in the Devices view, behind "Show past devices" (#583).
            filter: DeviceListFilter(search: searchText),
            presence: presence,
            sort: sortOrder,
            ascending: sortOrder == .lastSeen ? false : true
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                // Clickable title — opens full devices view
                Button {
                    showFullDevicesView = true
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(MacTheme.Colors.info)
                            .frame(width: 5, height: 5)
                        Text("NETWORK DEVICES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MacTheme.Colors.labelSecondary)
                            .tracking(1.4)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(MacTheme.Colors.labelTertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("networkDevicesPanel_button_openFullDevices")
                .help("Open full devices view")

                Spacer()

                // Scan button
                Button {
                    switch Self.scanTarget(
                        panelProfileID: networkProfileID,
                        profiles: profileManager?.profiles ?? [],
                        lastScanned: coordinator?.networkProfile
                    ) {
                    case .network(let profile): coordinator?.rescan(.user(profile))
                    case .startScan: coordinator?.rescan(.user(nil))
                    case .none: break
                    }
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                        .foregroundStyle(coordinator?.isScanning == true ? MacTheme.Colors.info : MacTheme.Colors.labelSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("networkDevicesPanel_button_scan")
                .disabled(coordinator?.isScanning == true)
                .help("Scan network")

                // Device count badge
                Text("\(filteredDevices.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(MacTheme.Colors.info.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))

                // Sort menu
                Menu {
                    ForEach(Self.sortOptions, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            HStack {
                                Label(order.panelLabel, systemImage: order.icon)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .accessibilityIdentifier("networkDevicesPanel_menu_sort\(order.panelLabel.lowercased())")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                }
                .accessibilityIdentifier("networkDevicesPanel_menu_sort")
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                TextField("Search devices...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.Colors.textPrimary)
                    .accessibilityIdentifier("networkDevicesPanel_textfield_search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(MacTheme.Colors.labelSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("networkDevicesPanel_button_clearSearch")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(MacTheme.Colors.chartSurfaceShallow, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MacTheme.Colors.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Device list
            if filteredDevices.isEmpty {
                Spacer()
                ContentUnavailableView(
                    coordinator?.isScanning == true ? "Scanning..." : "No Devices",
                    systemImage: coordinator?.isScanning == true ? "antenna.radiowaves.left.and.right" : "network",
                    description: Text(
                        coordinator?.isScanning == true
                            ? "Discovering devices on this network"
                            : searchText.isEmpty
                                ? "No devices discovered on this network yet"
                                : "No devices match your search"
                    )
                )
                .accessibilityIdentifier("networkDevicesPanel_label_empty")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredDevices) { device in
                            DevicePanelRow(device: device, isSelected: selectedDevice.map { device.contains($0.id) } ?? false)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedDevice = selectedDevice.map { device.contains($0.id) } == true ? nil : device.primary
                                }
                                .accessibilityIdentifier("networkDevicesPanel_row_\(device.ipAddress)")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("networkDevicesPanel_list_devices")
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius, padding: 0)
        .sheet(item: $selectedDevice) { device in
            ProDeviceDetailView(device: device)
                .frame(minWidth: 700, minHeight: 500)
        }
        .sheet(isPresented: $showFullDevicesView) {
            DevicesView(isSheet: true)
                .macThemedBackground()
                .frame(minWidth: 900, minHeight: 600)
        }
        .overlay {
            if coordinator?.isScanning == true {
                VStack(spacing: 8) {
                    ProgressView(value: coordinator?.scanProgress ?? 0)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 140)
                    Text("\(Int((coordinator?.scanProgress ?? 0) * 100))%")
                        .font(.caption2)
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(16)
                .allowsHitTesting(false)
            }
        }
    }

}

extension DeviceSortOrder {
    /// Label text for this panel's sort menu (distinct from `DevicesView`'s
    /// `.label`, which spells `.ipAddress` as "IP Address" rather than "IP").
    var panelLabel: String {
        switch self {
        case .status: return "Status"
        case .name: return "Name"
        case .ipAddress: return "IP"
        case .lastSeen: return "Last Seen"
        default: return rawValue
        }
    }
}

// MARK: - Device Panel Row

private struct DevicePanelRow: View {
    /// One device (#594): the primary's name, type and maker; the current member's address, MAC
    /// and latency; every member's open ports; the best member's presence.
    let device: DeviceProjection
    let isSelected: Bool

    @State private var isHovering = false
    @Environment(\.presence) private var presence

    var body: some View {
        HStack(spacing: 8) {
            PresenceDot(
                freshness: presence.freshness(of: device), size: 7,
                accessibilityText: presence.accessibilityText(device)
            )
            .shadow(color: presence.freshness(of: device).isOnline ? MacTheme.Colors.success.opacity(0.6) : .clear, radius: 3)

            // Device icon
            Image(systemName: device.primary.deviceType.iconName)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Colors.labelSecondary)
                .frame(width: 16)

            // Name + IP — flexible but capped
            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.Colors.textPrimary)
                    .lineLimit(1)

                Text(device.ipAddress)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MacTheme.Colors.textSecondary)
            }
            .frame(minWidth: 120, maxWidth: 200, alignment: .leading)

            // Vendor — constrained width
            Text(device.primary.makerLabel ?? "")
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.Colors.labelTertiary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            // MAC Address (last 8 chars)
            Text(device.current.macAddress.isEmpty ? "" : String(device.current.macAddress.suffix(8)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MacTheme.Colors.labelQuaternary)
                .frame(width: 70, alignment: .leading)

            // Open Ports (top 3)
            portsText
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MacTheme.Colors.info)
                .lineLimit(1)
                .frame(width: 70, alignment: .leading)

            Spacer(minLength: 4)

            // Latency — bright threshold-colored
            if let latency = presence.currentLatency(device), latency > 0 {
                Text(String(format: "%.1fms", latency))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(latencyColor(latency))
            } else if presence.freshness(of: device).isOnline {
                Text("--")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MacTheme.Colors.labelTertiary)
            }

            // How long ago it was last seen (#583); the dot already says it to VoiceOver.
            Text(presence.relativeLastSeen(device))
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.Colors.labelTertiary)
                .lineLimit(1)
                .frame(width: 70, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? MacTheme.Colors.sidebarActive.opacity(0.5)
                : (isHovering ? MacTheme.Colors.chartSurfaceShallow : Color.clear)
        )
        .onHover { isHovering = $0 }
    }

    private var portsText: some View {
        let ports = Set(device.members.flatMap { $0.openPorts ?? [] }).sorted()
        if ports.isEmpty {
            return Text("")
        } else {
            return Text(ports.prefix(3).map(String.init).joined(separator: ","))
        }
    }

    private func latencyColor(_ ms: Double) -> Color {
        switch ms {
        case ..<5:   return MacTheme.Colors.success
        case ..<20:  return MacTheme.Colors.info
        case ..<50:  return MacTheme.Colors.warning
        default:     return MacTheme.Colors.error
        }
    }
}

#if DEBUG
#Preview {
    NetworkDevicesPanel(networkProfileID: nil)
        .frame(width: 340, height: 500)
        .modelContainer(PreviewContainer().container)
}
#endif
