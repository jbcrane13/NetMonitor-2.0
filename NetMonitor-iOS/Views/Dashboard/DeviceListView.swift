import SwiftUI
import NetMonitorCore
import NetworkScanKit

enum DeviceSortOrder: String, CaseIterable {
    case ip = "IP Address"
    case name = "Name"
    case latency = "Latency"
    case source = "Source"
}

struct DeviceListView: View {
    let discoveredDevices: [DiscoveredDevice]
    let networkProfile: NetworkProfile?
    @State private var sortOrder: DeviceSortOrder = .ip
    @AppStorage("netmonitor.ios.devices.proMode") private var isProMode: Bool = false

    private var sortedDevices: [DiscoveredDevice] {
        switch sortOrder {
        case .ip:
            discoveredDevices.sorted { $0.ipAddress.ipSortKey < $1.ipAddress.ipSortKey }
        case .name:
            discoveredDevices.sorted {
                ($0.displayName).localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .latency:
            discoveredDevices.sorted { ($0.latency ?? 9999) < ($1.latency ?? 9999) }
        case .source:
            discoveredDevices.sorted {
                if $0.source == $1.source {
                    return $0.ipAddress.ipSortKey < $1.ipAddress.ipSortKey
                }
                return $0.source == .local
            }
        }
    }

    var body: some View {
        ScrollView {
            if discoveredDevices.isEmpty {
                ContentUnavailableView(
                    "No Devices Found",
                    systemImage: "network.slash",
                    description: Text("Run a network scan to discover devices")
                )
                .accessibilityIdentifier("deviceList_label_empty")
            } else {
                VStack(spacing: Theme.Layout.itemSpacing) {
                    // Sort control
                    HStack {
                        Text("\(discoveredDevices.count) devices")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)

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
                            ForEach(DeviceSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.Colors.accent)
                        .accessibilityIdentifier("deviceList_picker_sort")
                    }
                    .padding(.horizontal, Theme.Layout.screenPadding)

                    ForEach(sortedDevices) { device in
                        NavigationLink(destination: DeviceDetailView(ipAddress: device.ipAddress)) {
                            if isProMode {
                                proModeRow(device: device)
                            } else {
                                deviceRow(device: device)
                            }
                        }
                        .accessibilityIdentifier("deviceList_row_device_\(device.ipAddress.replacingOccurrences(of: ".", with: "_"))")
                    }
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.vertical, Theme.Layout.smallCornerRadius)
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

    @ViewBuilder
    private func deviceRow(device: DiscoveredDevice) -> some View {
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

                    if let vendor = device.vendor, !vendor.isEmpty {
                        Text(vendor)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func proModeRow(device: DiscoveredDevice) -> some View {
        GlassCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // Status dot
                    Circle()
                        .fill(Theme.Colors.success)
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

                if let vendor = device.vendor, !vendor.isEmpty {
                    Text(vendor)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func latencyColor(_ latency: Double?) -> Color {
        guard let ms = latency else { return Theme.Colors.textTertiary }
        if ms < 10 { return Theme.Colors.success }
        if ms < 50 { return Theme.Colors.warning }
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
            networkProfile: nil
        )
    }
}
