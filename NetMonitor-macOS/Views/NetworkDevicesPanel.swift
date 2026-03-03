import SwiftUI
import NetMonitorCore
import SwiftData

/// Full-height scrollable device grid scoped to a single network profile.
/// Embedded in NetworkDetailView as the right-column panel.
struct NetworkDevicesPanel: View {
    let networkProfileID: UUID?
    let networkProfile: NetworkProfile?

    @Environment(DeviceDiscoveryCoordinator.self) private var coordinator: DeviceDiscoveryCoordinator?
    @Query(sort: \LocalDevice.lastSeen, order: .reverse) private var allDevices: [LocalDevice]

    @State private var searchText: String = ""
    @State private var sortOrder: PanelSortOrder = .status
    @State private var selectedDevice: LocalDevice?
    @State private var showFullDevicesView = false

    enum PanelSortOrder: String, CaseIterable {
        case status   = "Status"
        case name     = "Name"
        case ipAddress = "IP"
        case lastSeen = "Last Seen"

        var icon: String {
            switch self {
            case .status:    return "circle.fill"
            case .name:      return "textformat"
            case .ipAddress: return "number"
            case .lastSeen:  return "clock"
            }
        }
    }

    private var filteredDevices: [LocalDevice] {
        var result = allDevices.filter { $0.networkProfileID == networkProfileID }

        if !searchText.isEmpty {
            result = result.filter { device in
                device.displayName.localizedCaseInsensitiveContains(searchText) ||
                device.ipAddress.contains(searchText) ||
                device.macAddress.localizedCaseInsensitiveContains(searchText) ||
                (device.vendor?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        switch sortOrder {
        case .status:
            result.sort { ($0.status == .online ? 0 : 1) < ($1.status == .online ? 0 : 1) }
        case .name:
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .ipAddress:
            result.sort { compareIPAddresses($0.ipAddress, $1.ipAddress) }
        case .lastSeen:
            result.sort { $0.lastSeen > $1.lastSeen }
        }

        return result
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
                            .foregroundStyle(.secondary)
                            .tracking(1.4)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .help("Open full devices view")

                Spacer()

                // Scan button
                Button {
                    if let profile = networkProfile {
                        coordinator?.scanNetwork(profile)
                    } else if let profile = coordinator?.networkProfile {
                        coordinator?.scanNetwork(profile)
                    } else {
                        coordinator?.startScan()
                    }
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11))
                        .foregroundStyle(coordinator?.isScanning == true ? MacTheme.Colors.info : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(coordinator?.isScanning == true)
                .help("Scan network")

                // Device count badge
                Text("\(filteredDevices.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(MacTheme.Colors.info.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                // Sort menu
                Menu {
                    ForEach(PanelSortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            HStack {
                                Label(order.rawValue, systemImage: order.icon)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
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
                    .foregroundStyle(.secondary)
                TextField("Search devices...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
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
                .accessibilityIdentifier("network_devices_panel_empty")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredDevices) { device in
                            DevicePanelRow(device: device, isSelected: selectedDevice?.id == device.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedDevice = selectedDevice?.id == device.id ? nil : device
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("network_devices_panel_list")
            }
        }
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius, padding: 0)
        .sheet(item: $selectedDevice) { device in
            DeviceDetailView(device: device)
                .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showFullDevicesView) {
            DevicesView()
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
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(16)
                .allowsHitTesting(false)
            }
        }
    }

    private func compareIPAddresses(_ a: String, _ b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<min(aParts.count, bParts.count) {
            if aParts[i] != bParts[i] { return aParts[i] < bParts[i] }
        }
        return aParts.count < bParts.count
    }
}

// MARK: - Device Panel Row

private struct DevicePanelRow: View {
    let device: LocalDevice
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(device.status == .online ? MacTheme.Colors.success : Color.gray.opacity(0.5))
                .frame(width: 7, height: 7)
                .shadow(color: device.status == .online ? MacTheme.Colors.success.opacity(0.6) : .clear, radius: 3)

            // Device icon
            Image(systemName: device.deviceType.iconName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            // Name + IP
            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(device.ipAddress)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Vendor
            if let vendor = device.vendor {
                Text(vendor)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Latency — bright threshold-colored
            if let latency = device.lastLatency, latency > 0 {
                Text(String(format: "%.1fms", latency))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(latencyColor(latency))
            } else if device.status == .online {
                Text("--")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? MacTheme.Colors.sidebarActive.opacity(0.5)
                : (isHovering ? Color.white.opacity(0.04) : Color.clear)
        )
        .onHover { isHovering = $0 }
    }

    private func latencyColor(_ ms: Double) -> Color {
        switch ms {
        case ..<5:   return MacTheme.Colors.success          // green
        case ..<20:  return MacTheme.Colors.info             // blue
        case ..<50:  return MacTheme.Colors.warning          // yellow/amber
        default:     return MacTheme.Colors.error            // red
        }
    }
}

#if DEBUG
#Preview {
    NetworkDevicesPanel(networkProfileID: nil, networkProfile: nil)
        .frame(width: 340, height: 500)
        .modelContainer(PreviewContainer().container)
}
#endif
