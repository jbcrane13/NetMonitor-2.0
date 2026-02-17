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
    @State private var sortOrder: DeviceSortOrder = .ip

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
                            deviceRow(device: device)
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
        .accessibilityIdentifier("deviceList_screen")
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
}

#Preview {
    NavigationStack {
        DeviceListView(discoveredDevices: [
            DiscoveredDevice(ipAddress: "192.168.1.1", latency: 5.2, discoveredAt: Date()),
            DiscoveredDevice(ipAddress: "192.168.1.100", latency: 12.8, discoveredAt: Date()),
            DiscoveredDevice(ipAddress: "192.168.1.200", latency: 8.1, discoveredAt: Date())
        ])
    }
}
