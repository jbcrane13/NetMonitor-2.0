//
//  QuickJumpSheet.swift
//  NetMonitor-macOS
//
//  ⌘K quick-jump overlay for rapidly navigating to a device by name or IP.
//  Styled as a Spotlight-like search field with filtered results below.
//

import SwiftUI
import SwiftData
import NetMonitorCore

struct QuickJumpSheet: View {
    @Binding var selection: SidebarSelection?
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.presence) private var presence
    @Query(LocalDeviceQueries.recents()) private var devices: [LocalDevice]

    @State private var searchText: String = ""
    @FocusState private var isFocused: Bool

    private var filteredDevices: [DeviceProjection] {
        // `devices` (the query) only triggers the refresh; devices are paged by device (#594).
        devices.isEmpty ? [] : Self.results(LocalDeviceQueries.recentDevices(in: .allNetworks, in: modelContext), search: searchText)
    }

    /// The first 8 devices matching `search` (#594: one entry per device, searched across every
    /// interface's name, address, maker and hostname).
    static func results(_ devices: [DeviceProjection], search: String) -> [DeviceProjection] {
        guard !search.isEmpty else {
            return Array(devices.prefix(8))
        }
        let query = search.lowercased()
        return devices.filter { device in
            device.displayName.lowercased().contains(query) || device.members.contains { member in
                member.displayName.lowercased().contains(query) ||
                    member.ipAddress.lowercased().contains(query) ||
                    (member.maker?.lowercased().contains(query) ?? false) ||
                    (member.hostname?.lowercased().contains(query) ?? false)
            }
        }
        .prefix(8)
        .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .font(.system(size: 16))

                TextField("Jump to device…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isFocused)
                    .accessibilityIdentifier("quickJump_textfield_search")
                    .onSubmit {
                        if let first = filteredDevices.first {
                            navigateToDevice(first)
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MacTheme.Colors.labelTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quickJump_button_clearSearch")
                }

                Text("⌘K")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MacTheme.Colors.labelTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(MacTheme.Colors.chartSurfaceShallow, in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Results
            if filteredDevices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(MacTheme.Colors.labelTertiary)
                    Text("No devices found")
                        .font(.caption)
                        .foregroundStyle(MacTheme.Colors.labelSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredDevices) { device in
                            quickJumpRow(device: device)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            isPresented = false
        }
    }

    private func quickJumpRow(device: DeviceProjection) -> some View {
        Button {
            navigateToDevice(device)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(MacTheme.Colors.presenceColor(presence.freshness(of: device)).opacity(0.2))
                        .frame(width: 28, height: 28)

                    Image(systemName: device.primary.deviceType.iconName)
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.Colors.presenceColor(presence.freshness(of: device)))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacTheme.Colors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(device.ipAddress)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MacTheme.Colors.labelSecondary)

                        if let maker = device.primary.maker {
                            Text("·")
                                .foregroundStyle(MacTheme.Colors.labelTertiary)
                            Text(maker)
                                .font(.system(size: 10))
                                .foregroundStyle(MacTheme.Colors.labelTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                PresenceStatusLabel(device: device, font: .system(size: 10))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(MacTheme.Colors.chartSurfaceShallow)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quickJump_row_\(device.id)")
    }

    private func navigateToDevice(_ device: DeviceProjection) {
        // Navigate to the Devices section — the device detail can be reached from there
        selection = .section(.devices)
        isPresented = false
    }
}

#if DEBUG
#Preview {
    @Previewable @State var selection: SidebarSelection? = nil
    @Previewable @State var isPresented = true

    QuickJumpSheet(selection: $selection, isPresented: $isPresented)
        .modelContainer(PreviewContainer().container)
}
#endif
