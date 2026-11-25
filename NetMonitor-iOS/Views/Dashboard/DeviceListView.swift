import SwiftUI
import SwiftData
import NetMonitorCore
import NetworkScanKit

enum DeviceSortOrder: String, CaseIterable {
    case ip = "IP Address"
    case name = "Name"
    case latency = "Latency"
    case source = "Source"
}

struct DeviceListView: View {
    /// The scan's devices, during or after it: those not saved yet show as found in this scan.
    let discoveredDevices: [DiscoveredDevice]
    let networkProfile: NetworkProfile?
    /// The network whose saved rows the list shows (#583): the scan's, else the active one.
    let networkID: UUID?
    let isScanning: Bool
    @Query private var savedDevices: [LocalDevice]
    @Environment(DevicePresenceModel.self) private var presenceModel: DevicePresenceModel?
    @State private var sortOrder: SavedDeviceList.Sort = .ip
    /// Past devices (unseen for a week) are hidden each time the list opens, never remembered
    /// hidden: the list always says how many there are, so none is hidden without a way back.
    @State private var showPastDevices = false
    @AppStorage("netmonitor.ios.devices.proMode") private var isProMode: Bool = false

    init(discoveredDevices: [DiscoveredDevice], networkProfile: NetworkProfile?, networkID: UUID?, isScanning: Bool = false) {
        self.discoveredDevices = discoveredDevices
        self.networkProfile = networkProfile
        self.networkID = networkID
        self.isScanning = isScanning
        _savedDevices = Query(SavedDeviceList.fetchDescriptor(network: networkID))
    }

    var body: some View {
        // The presence model refreshes after each saved scan and every minute.
        let list = SavedDeviceList(
            saved: savedDevices, live: discoveredDevices, network: networkID, sort: sortOrder, showPast: showPastDevices,
            presence: presenceModel?.snapshot ?? DevicePresenceModel.noScans
        )
        ScrollView {
            if list.entries.isEmpty, list.pastCount == 0, !isScanning {
                ContentUnavailableView(
                    "No Devices Found",
                    systemImage: "network.slash",
                    description: Text("Run a network scan to discover devices")
                )
                .accessibilityIdentifier("deviceList_label_empty")
            } else {
                content(list)
            }
        }
        .themedBackground()
        .navigationTitle("Local Devices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isProMode.toggle()
                } label: {
                    Image(systemName: isProMode ? "list.bullet.rectangle" : "list.bullet")
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityIdentifier("deviceList_button_toggleViewMode")
            }
        }
        .accessibilityIdentifier("screen_deviceList")
    }

    // MARK: - Rows (#583)

    private func content(_ list: SavedDeviceList) -> some View {
        VStack(spacing: Theme.Layout.itemSpacing) {
            header(count: "\(list.onlineCount) online · \(list.entries.count) devices")

            if isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning…")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Layout.screenPadding)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("deviceList_label_scanning")
            }

            ForEach(list.entries) { entry in
                switch entry {
                case .saved(let device):
                    savedLink(device, in: list)
                case .found(let device):
                    foundLink(device, in: list)
                }
            }

            if list.pastCount > 0 {
                Button(showPastDevices ? "Hide past devices" : "Show past devices (\(list.pastCount))") {
                    showPastDevices.toggle()
                }
                .font(.subheadline)
                .tint(Theme.Colors.accent)
                .padding(.vertical, 8)
                .accessibilityIdentifier("deviceList_button_showPast")
            }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, Theme.Layout.smallCornerRadius)
    }

    private func savedLink(_ device: LocalDevice, in list: SavedDeviceList) -> some View {
        NavigationLink(value: SavedDeviceList.Entry.saved(device).destination) {
            if isProMode {
                savedProModeRow(device, in: list)
            } else {
                savedRow(device, in: list)
            }
        }
        .opacity(list.presence.freshness(of: device).isOnline ? 1 : 0.7)
        // The row's value says the state once; the visible status line is hidden from VoiceOver.
        .accessibilityValue(list.presence.accessibilityText(device))
        .accessibilityIdentifier("deviceList_row_device_\(device.ipAddress.replacingOccurrences(of: ".", with: "_"))")
    }

    /// A device this scan found that has no saved row yet.
    private func foundLink(_ device: DiscoveredDevice, in list: SavedDeviceList) -> some View {
        NavigationLink(value: SavedDeviceList.Entry.found(device).destination) {
            if isProMode {
                proModeRow(device: device, foundText: list.foundText(device))
            } else {
                deviceRow(device: device, foundText: list.foundText(device))
            }
        }
        .opacity(list.freshness(of: device).isOnline ? 1 : 0.7)
        .accessibilityValue(list.foundText(device))
        .accessibilityIdentifier("deviceList_row_device_\(device.ipAddress.replacingOccurrences(of: ".", with: "_"))")
    }

    private func savedRow(_ device: LocalDevice, in list: SavedDeviceList) -> some View {
        GlassCard {
            HStack(spacing: Theme.Layout.itemSpacing) {
                Image(systemName: device.deviceType.iconName)
                    .foregroundStyle(Theme.Colors.accent)
                    .font(.title2)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    HStack(spacing: 8) {
                        Text(device.ipAddress)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        if let latency = list.latencyText(device) {
                            Text(latency)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }

                    PresenceLine(
                        freshness: list.presence.freshness(of: device), text: list.presence.statusText(device),
                        accessibilityID: "deviceList_label_presence_\(device.ipAddress.replacingOccurrences(of: ".", with: "_"))"
                    )
                        .accessibilityHidden(true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func savedProModeRow(_ device: LocalDevice, in list: SavedDeviceList) -> some View {
        GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    PresenceDot(freshness: list.presence.freshness(of: device))
                    Text(device.ipAddress)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if let latency = list.latencyText(device) {
                        Text(latency)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(latencyColor(device.lastLatency))
                    }
                }
                Text(device.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                Text(list.presence.statusText(device))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(count: String) -> some View {
        HStack {
            Text(count)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("deviceList_label_count")

            if isProMode {
                Text("PRO")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.accent.opacity(0.15))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("deviceList_label_proMode")
            }

            if let networkProfile {
                Label(networkProfile.displayName, systemImage: networkProfile.connectionType.iconName)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Colors.accent.opacity(0.16))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("deviceList_label_network")
            } else {
                Label("Auto", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.Colors.accent.opacity(0.16))
                    .clipShape(Capsule())
                    .accessibilityIdentifier("deviceList_label_network")
            }

            Spacer()
            Picker("Sort", selection: $sortOrder) {
                ForEach(SavedDeviceList.Sort.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.Colors.accent)
            .accessibilityIdentifier("deviceList_picker_sort")
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
    }

    private func deviceRow(device: DiscoveredDevice, foundText: String) -> some View {
        GlassCard {
            HStack(spacing: Theme.Layout.itemSpacing) {
                Image(systemName: device.source == .macCompanion ? "desktopcomputer.and.arrow.down" : "desktopcomputer")
                    .foregroundStyle(Theme.Colors.accent)
                    .font(.title2)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    HStack(spacing: 8) {
                        if device.hostname != nil {
                            Text(device.ipAddress)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }

                        Text(device.latencyText)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    if let vendor = device.makerLabel {
                        Text(vendor)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    Label(foundText, systemImage: "sparkle")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.accent)
                        .accessibilityHidden(true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func proModeRow(device: DiscoveredDevice, foundText: String) -> some View {
        GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // Status dot
                    Circle()
                        .fill(device.isCached ? Theme.Colors.warning : Theme.Colors.success)
                        .frame(width: 6, height: 6)

                    // IP Address (monospaced, prominent)
                    Text(device.ipAddress)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer()

                    // Latency
                    Text(device.latencyText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(latencyColor(device.latency))
                }

                HStack(spacing: 12) {
                    // Name
                    Text(device.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    // Source badge
                    Text(sourceBadgeLabel(device.source))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(sourceBadgeColor(device.source))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sourceBadgeColor(device.source).opacity(0.15))
                        .clipShape(Capsule())
                }

                if let vendor = device.makerLabel {
                    Text(vendor)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }

                Text(foundText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func latencyColor(_ latency: Double?) -> Color {
        guard let ms = latency else { return Theme.Colors.textTertiary }
        if ms < 10 {
            return Theme.Colors.success
        }
        if ms < 50 {
            return Theme.Colors.warning
        }
        return Theme.Colors.error
    }

    private func sourceBadgeLabel(_ source: DeviceSource) -> String {
        switch source {
        case .macCompanion: return "Mac"
        case .bonjour: return "Bonjour"
        case .ssdp: return "UPnP"
        case .local: return "Local"
        }
    }

    private func sourceBadgeColor(_ source: DeviceSource) -> Color {
        switch source {
        case .macCompanion: return Theme.Colors.accent
        case .bonjour: return Theme.Colors.warning
        case .ssdp: return Theme.Colors.warning
        case .local: return Theme.Colors.textTertiary
        }
    }
}

#Preview {
    NavigationStack {
        DeviceListView(
            discoveredDevices: [
                DiscoveredDevice(ipAddress: "192.168.1.1", latency: 5.2, discoveredAt: Date()),
                DiscoveredDevice(ipAddress: "192.168.1.100", latency: 12.8, discoveredAt: Date()),
                DiscoveredDevice(ipAddress: "192.168.1.200", latency: 8.1, discoveredAt: Date())
            ],
            networkProfile: nil,
            networkID: nil
        )
    }
}
