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
    @Query(sort: \LocalDevice.lastSeen, order: .reverse) private var devices: [LocalDevice]

    @State private var searchText: String = ""
    @FocusState private var isFocused: Bool

    private var filteredDevices: [LocalDevice] {
        guard !searchText.isEmpty else {
            return Array(devices.prefix(8))
        }
        let query = searchText.lowercased()
        return devices.filter { device in
            device.displayName.lowercased().contains(query) ||
            device.ipAddress.lowercased().contains(query) ||
            (device.vendor?.lowercased().contains(query) ?? false) ||
            (device.hostname?.lowercased().contains(query) ?? false)
        }
        .prefix(8)
        .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
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
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quickJump_button_clearSearch")
                }

                Text("⌘K")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Results
            if filteredDevices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No devices found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private func quickJumpRow(device: LocalDevice) -> some View {
        Button {
            navigateToDevice(device)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(device.status == .online ? MacTheme.Colors.success.opacity(0.2) : Color.gray.opacity(0.2))
                        .frame(width: 28, height: 28)

                    Image(systemName: device.deviceType.iconName)
                        .font(.system(size: 12))
                        .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .gray)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(device.ipAddress)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if let vendor = device.vendor {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(vendor)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Circle()
                    .fill(device.status == .online ? MacTheme.Colors.success : Color.gray)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quickJump_row_\(device.id)")
    }

    private func navigateToDevice(_ device: LocalDevice) {
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
